#!/bin/bash

set -e

echo "--- Starting container setup ---"

echo "Installing dependencies: curl, unzip..."
pac -Syu --noconfirm curl unzip

export BUN_INSTALL="/app/bun"
export PATH="$BUN_INSTALL/bin:$PATH"

echo "Installing bun to $BUN_INSTALL..."
mkdir -p "$BUN_INSTALL"
curl -fsSL https://bun.sh/install | bash

echo "Verifying bun installation..."
$BUN_INSTALL/bin/bun --version

echo "Installing @anthropic-ai/claude-code..."
$BUN_INSTALL/bin/bun install -g @anthropic-ai/claude-code

echo "Creating autorun wrapper script at /app/bin/claude..."
mkdir -p /app/bin
cat <<'EOWrapper' >/app/bin/claude
#!/bin/bash

exec /app/bun/bin/bun /app/bun/bin/claude "$@"
EOWrapper

chmod +x /app/bin/claude
echo "--- Container setup complete. ---"
