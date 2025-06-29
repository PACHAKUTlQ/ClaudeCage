#!/bin/bash

# ==============================================================================
# ClaudeCage Build Script
#
# This script automates the creation of a portable, sandboxed RunImage
# container for the 'claude-code' CLI tool. It performs all actions in a
# temporary directory and does not modify the host system.
#
# The final output is two files:
#   - 'ClaudeCage': The single-file executable.
#   - 'ClaudeCage.rcfg': The sandboxing configuration file.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
PROJECT_NAME="ClaudeCage"
RUNIMAGE_URL="https://github.com/VHSgunzo/runimage/releases/download/continuous/runimage-x86_64"
ORIGINAL_CWD=$(pwd)

# --- Functions ---

# Function to print colored messages
print_info() {
  echo -e "\n\e[34m\e[1m[INFO]\e[0m $1"
}

print_success() {
  echo -e "\e[32m\e[1m[SUCCESS]\e[0m $1\n"
}

print_error() {
  echo -e "\e[31m\e[1m[ERROR]\e[0m $1" >&2
}

# Cleanup function to be called on script exit
cleanup() {
  if [ -d "$BUILD_DIR" ]; then
    print_info "Cleaning up temporary build directory..."
    # If the OverlayFS still exists, try to remove it
    if [ -f "$BUILD_DIR/runimage" ] && [ -n "$BUILD_ID" ]; then
      "$BUILD_DIR/runimage" rim-ofsrm "$BUILD_ID" &>/dev/null || true
    fi
    rm -rf "$BUILD_DIR"
  fi
}

# --- Script Start ---

trap cleanup EXIT ERR INT
BUILD_DIR=$(mktemp -d -t claude-cage-build-XXXXXX)
print_info "Created temporary build directory at: $BUILD_DIR"
cd "$BUILD_DIR"

# --- Step 1: Get and Verify RunImage ---
print_info "Acquiring RunImage..."
# Check if a local copy exists to save bandwidth, otherwise download it.
if [ -f "$ORIGINAL_CWD/runimage" ]; then
  echo "Found 'runimage' in the project directory. Copying it."
  cp "$ORIGINAL_CWD/runimage" .
elif [ -f "$ORIGINAL_CWD/runimage-x86_64" ]; then
  echo "Found 'runimage-x86_64' in the project directory. Copying it."
  cp "$ORIGINAL_CWD/runimage-x86_64" ./runimage
else
  echo "Downloading RunImage..."
  if ! curl -# -Lo runimage "$RUNIMAGE_URL"; then
    print_error "Failed to download RunImage. Please check your internet connection."
    exit 1
  fi
fi
chmod +x runimage

print_info "Verifying RunImage integrity..."
RUNIMAGE_HASH=$(sha256sum runimage | awk '{print $1}')
if ! curl -s https://api.github.com/repos/VHSgunzo/runimage/releases/latest | grep -q "$RUNIMAGE_HASH  runimage-x86_64"; then
  print_error "RunImage verification failed!"
  print_error "Please delete the local 'runimage' file and try again."
  exit 1
fi
print_info "RunImage is valid and ready."

# --- Step 2: Create the Inner Setup Script ---
print_info "Preparing the container setup script..."
cat <<'EOF' >setup_in_container.sh
#!/bin/bash
set -e

echo "--- Starting container setup ---"

echo "Installing dependencies: curl, unzip..."
pac -Syu --noconfirm curl unzip

export BUN_INSTALL="/opt/bun"
export PATH="$BUN_INSTALL/bin:$PATH"

echo "Installing bun to $BUN_INSTALL..."
mkdir -p "$BUN_INSTALL"
curl -fsSL https://bun.sh/install | bash

echo "Verifying bun installation..."
$BUN_INSTALL/bin/bun --version

echo "Installing @anthropic-ai/claude-code..."
$BUN_INSTALL/bin/bun install -g @anthropic-ai/claude-code

echo "Creating autorun wrapper script at /usr/local/bin/claude..."
cat <<'EOWrapper' > /usr/local/bin/claude
#!/bin/bash
exec /opt/bun/bin/bun /opt/bun/bin/claude "$@"
EOWrapper

chmod +x /usr/local/bin/claude
echo "--- Container setup complete. ---"
EOF
chmod +x setup_in_container.sh

# --- Step 3: Build the Custom RunImage ---
print_info "Starting the build process..."
BUILD_ID="claude-cage-build-$$"

# Run the setup script inside the container's temporary "workshop" environment.
# RIM_OVERFS_ID/RIM_KEEP_OVERFS: Manages the writable layer.
# RIM_BIND: Mounts the build directory so the container can access the setup script.
if ! RIM_OVERFS_ID="$BUILD_ID" \
  RIM_KEEP_OVERFS=1 \
  RIM_BIND="$PWD:/build" \
  ./runimage rim-shell -c "bash /build/setup_in_container.sh"; then
  print_error "The container setup script failed."
  exit 1
fi

# --- Step 4: Build the Final Executable ---
print_info "Container setup was successful. Now building the final executable..."
# Use the OverlayFS to build the new, self-contained RunImage.
if ! RIM_OVERFS_ID="$BUILD_ID" \
  ./runimage rim-build "./${PROJECT_NAME}"; then
  print_error "Failed to build the final ${PROJECT_NAME} executable."
  exit 1
fi

# --- Step 5: Finalize and Create Config ---
print_info "Finalizing the build..."
mv "./${PROJECT_NAME}" "$ORIGINAL_CWD/"

print_info "Creating the sandbox configuration file (${PROJECT_NAME}.rcfg)..."
cat <<EOF >"$ORIGINAL_CWD/${PROJECT_NAME}.rcfg"
# --- ${PROJECT_NAME} Sandbox Configuration ---

# --- 1. AUTORUN ---
# claude wrapper in /usr/local/bin that runs claude code using bun
RIM_AUTORUN=("claude")

# --- 2. ENVIRONMENT VARIABLES ---
export DISABLE_AUTOUPDATER=1
export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1
export DISABLE_TELEMETRY=1

# --- 3. SANDBOXING RULES ---

# Bind claude's config, data and cache directory
RIM_BIND+=("$HOME/.claude.json:$HOME/.claude.json")
RIM_BIND+=("$HOME/.claude:$HOME/.claude")

# This creates a writable /home in RAM, allowing the bind mount to work.
RIM_TMP_HOME=1

# Bind the current working directory from the host into the container.
RIM_BIND_PWD=1

# Start the 'claude' command in the same working directory.
RIM_EXEC_SAME_PWD=1

# For better isolation, unshare other common host resources.
RIM_UNSHARE_TMP=1
RIM_UNSHARE_PIDS=1
RIM_UNSHARE_USERS=1
RIM_UNSHARE_HOSTNAME=1
EOF

# --- Success Message ---
print_success "Build complete!"
echo "Your sandboxed application is ready:"
echo "  - Executable: ${ORIGINAL_CWD}/${PROJECT_NAME}"
echo "  - Config:     ${ORIGINAL_CWD}/${PROJECT_NAME}.rcfg"
echo
echo "To use it, navigate to your project directory and run:"
echo -e "  \e[1mcd /path/to/your/project\e[0m"
echo -e "  \e[1m/path/to/${PROJECT_NAME} [claude arguments]\e[0m"
