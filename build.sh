#!/usr/bin/env bash

# ==============================================================================
# ClaudeCage Build Script
#
# This script automates the creation of a portable, sandboxed RunImage
# container for the 'claude-code' CLI tool. It performs all actions in a
# temporary directory and does not modify the host system.
#
# The final output is two files:
#   - 'claude': The single-file executable.
#   - 'claude.rcfg': The sandboxing configuration file.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- Configuration ---
PROJECT_NAME="claude"
RUNIMAGE_TAG="continuous"
RUNIMAGE_ASSET="runimage-x86_64"
RUNIMAGE_URL="https://github.com/VHSgunzo/runimage/releases/download/${RUNIMAGE_TAG}/${RUNIMAGE_ASSET}"
RUNIMAGE_API="https://api.github.com/repos/VHSgunzo/runimage/releases/tags/${RUNIMAGE_TAG}"
ORIGINAL_CWD="$(pwd)"

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

# These must exist before trap (set -u)
BUILD_DIR=""
BUILD_ID=""

verify_local_runimage() {
  local rim_path="$1"
  print_info "Verifying local RunImage integrity..."
  local hash
  hash="$(sha256sum "${rim_path}" | awk '{print $1}')"
  if ! curl -fsSL "${RUNIMAGE_API}" | grep -Fq "${hash}"; then
    print_error "RunImage verification failed!"
    print_error "Hash: ${hash}"
    print_error "API:  ${RUNIMAGE_API}"
    print_error "Delete/replace your local '${RUNIMAGE_ASSET}' (or 'runimage') and retry."
    exit 1
  fi
}

# Cleanup function to be called on script exit
cleanup() {
  set +e
  if [[ -n "${BUILD_DIR:-}" && -d "${BUILD_DIR:-}" ]]; then
    print_info "Cleaning up temporary build directory..."
    # If the OverlayFS still exists, try to remove it
    if [[ -x "${BUILD_DIR}/runimage" && -n "${BUILD_ID:-}" ]]; then
      "${BUILD_DIR}/runimage" rim-ofsrm "${BUILD_ID}" &>/dev/null || true
    fi
    rm -rf "${BUILD_DIR}"
  fi
}

trap cleanup EXIT ERR INT

# --- Script Start ---

BUILD_DIR=$(mktemp -d -t claude-cage-build-XXXXXX)
print_info "Created temporary build directory at: ${BUILD_DIR}"
cd "${BUILD_DIR}"

# --- Step 1: Get and Verify RunImage ---
print_info "Acquiring RunImage..."
RUNIMAGE_FROM_LOCAL=0
# Check if a local copy exists to save bandwidth, otherwise download it.
if [ -f "${ORIGINAL_CWD}/runimage" ]; then
  echo "Found 'runimage' in the project directory. Copying it."
  cp "${ORIGINAL_CWD}/runimage" .
  RUNIMAGE_FROM_LOCAL=1
elif [ -f "${ORIGINAL_CWD}/${RUNIMAGE_ASSET}" ]; then
  echo "Found '${RUNIMAGE_ASSET}' in the project directory. Copying it."
  cp "${ORIGINAL_CWD}/${RUNIMAGE_ASSET}" ./runimage
  RUNIMAGE_FROM_LOCAL=1
else
  echo "Downloading RunImage..."
  if ! curl -fL# -o runimage "${RUNIMAGE_URL}"; then
    print_error "Failed to download RunImage. Please check your internet connection."
    exit 1
  fi
fi
chmod +x ./runimage

if [ "${RUNIMAGE_FROM_LOCAL}" -eq 1 ]; then
  verify_local_runimage ./runimage
else
  print_info "RunImage downloaded from GitHub HTTPS. Skipping hash verification."
fi
print_info "RunImage is valid and ready."

# --- Step 2: Create the Inner Setup Script ---
print_info "Preparing the container setup script..."
cat <<'EOF' >setup_in_container.sh
#!/usr/bin/env bash

set -euo pipefail

echo "--- Starting container setup ---"

echo "Installing dependencies: curl, unzip and ca-certificates..."
pac -Syu --noconfirm --needed curl unzip ca-certificates

export BUN_INSTALL="/app/bun"
export PATH="${BUN_INSTALL}/bin:${PATH}"

echo "Installing bun to ${BUN_INSTALL}..."
mkdir -p "${BUN_INSTALL}"
curl -fsSL https://bun.sh/install | bash

echo "Verifying bun installation..."
${BUN_INSTALL}/bin/bun --version

echo "Installing @anthropic-ai/claude-code..."
${BUN_INSTALL}/bin/bun install -g @anthropic-ai/claude-code

echo "Creating wrapper at /app/bin/claude..."
install -d -m 0755 /app/bin
cat >/app/bin/claude <<'EOW'
#!/usr/bin/env bash

set -euo pipefail

exec /app/bun/bin/bun /app/bun/bin/claude "$@"
EOW

chmod +x /app/bin/claude

echo "Shrinking image (pkg cache + docs)..."
RIM_SHRINK_PKCACHE=1 RIM_SHRINK_DOCS=1 rim-shrink "${RUNDIR}"

echo "--- Container setup complete. ---"
EOF
chmod +x setup_in_container.sh

# --- Step 3: Build the Custom RunImage ---
print_info "Starting the build process..."
BUILD_ID="claude-cage-build-$$"

# Run the setup script inside the container's temporary "workshop" environment.
# RIM_OVERFS_ID/RIM_KEEP_OVERFS: Manages the writable layer.
# RIM_BIND: Mounts the build directory so the container can access the setup script.
if ! RIM_OVERFS_ID="${BUILD_ID}" \
  RIM_KEEP_OVERFS=1 \
  RIM_BIND="${PWD}:/build" \
  ./runimage rim-shell -c "bash /build/setup_in_container.sh"; then
  print_error "The container setup script failed."
  exit 1
fi

# --- Step 4: Build the Final Executable ---
print_info "Container setup was successful. Now building the final executable..."
# Use the OverlayFS to build the new, self-contained RunImage.
if ! RIM_OVERFS_ID="${BUILD_ID}" \
  ./runimage rim-build "./${PROJECT_NAME}"; then
  print_error "Failed to build the final ${PROJECT_NAME} executable."
  exit 1
fi

# --- Step 5: Finalize and Create Config ---
print_info "Finalizing the build..."
mv "./${PROJECT_NAME}" "${ORIGINAL_CWD}/"

print_info "Creating the sandbox configuration file (${PROJECT_NAME}.rcfg)..."
cat <<'EOF' >"${ORIGINAL_CWD}/${PROJECT_NAME}.rcfg"
#!/hint/bash
# ClaudeCage RunImage config (.rcfg)

# Autorun (wrapper lives outside /usr because host /usr will be ro-bound)
RIM_AUTORUN=("/app/bin/claude")

# Claude Code env knobs
export DISABLE_AUTOUPDATER=1
export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1
export DISABLE_TELEMETRY=1

export BUN_INSTALL="/app/bun"
export PATH="/app/bin:/app/bun/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:/sbin"

# Ensure host Claude state exists (host-side, before sandbox starts)
umask 077
install -d -m 700 "${HOME}/.claude"
if [[ ! -e "${HOME}/.claude.json" ]]; then
  : > "${HOME}/.claude.json"
  chmod 600 "${HOME}/.claude.json" || true
fi

# Persist Claude state in standard host locations
RIM_BIND="${HOME}/.claude.json:${HOME}/.claude.json,${HOME}/.claude:${HOME}/.claude"

# Writable container HOME (tmpfs), while explicit binds above persist on host
RIM_TMP_HOME=1

# Bind the current working directory from the host into the container.
RIM_BIND_PWD=1

# Start the 'claude' command in the same working directory.
RIM_EXEC_SAME_PWD=1

# Host toolchain access (read-only)
RIM_BIND_RO="/usr:/usr,/opt:/opt,/etc:/etc"
[[ -e /lib   ]] && RIM_BIND_RO+=",/lib:/lib"
[[ -e /lib64 ]] && RIM_BIND_RO+=",/lib64:/lib64"
[[ -e /bin   ]] && RIM_BIND_RO+=",/bin:/bin"
[[ -e /sbin  ]] && RIM_BIND_RO+=",/sbin:/sbin"

# SSH for git: forward agent socket ONLY (no ~/.ssh by default)
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
  RIM_BIND+=",${SSH_AUTH_SOCK}:/tmp/ssh-agent.sock"
  export SSH_AUTH_SOCK="/tmp/ssh-agent.sock"
fi

# If you must allow reading host SSH keys/config (less secure):
#   CLAUDECAGE_ALLOW_SSH_KEYS=1 ./ClaudeCage ...
if [[ "${CLAUDECAGE_ALLOW_SSH_KEYS:-0}" == "1" && -d "${HOME}/.ssh" ]]; then
  RIM_BIND_RO+=",${HOME}/.ssh:${HOME}/.ssh"
fi

# For better isolation, unshare other common host resources.
RIM_UNSHARE_TMP=1
RIM_UNSHARE_PIDS=1
RIM_UNSHARE_USERS=1
RIM_UNSHARE_HOSTNAME=1
RIM_UNSHARE_DBUS=1
RIM_UNSHARE_XDGRUN=1
RIM_UNSHARE_TMPX11UNIX=1
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
