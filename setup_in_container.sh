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
cat <<'EOWrapper' >/usr/local/bin/claude
#!/bin/bash

exec /opt/bun/bin/bun /opt/bun/bin/claude "$@"
EOWrapper

chmod +x /usr/local/bin/claude
echo "--- Container setup complete. ---"
