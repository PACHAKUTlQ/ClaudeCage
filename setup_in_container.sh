#!/usr/bin/env bash

set -euo pipefail

echo "--- Starting container setup ---"

echo "Installing dependencies: curl, unzip and ca-certificates..."
pac -Syu --noconfirm --needed curl unzip ca-certificates

export BUN_INSTALL="/app/bun"
export PATH="${BUN_INSTALL}/bin:$PATH"

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
