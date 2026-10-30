#!/usr/bin/env bash
# ==============================================================================
# Base Container Entrypoint: It's a Plan AI Agent Runner
# Configures SSH keys, Git safety hooks, optional runner version sync,
# MCP configuration, /entrypoint.d/*.sh project hooks, and launches the runner.
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo "🚀 Starting It's a Plan Agent Runner on $(uname -m)..."
echo "=========================================================="

# 1. Setup SSH deploy keys from mounted /etc/ssh-keys if available
mkdir -p /root/.ssh
chmod 700 /root/.ssh
for host in github.com git.kms-lab.in.ua; do
    ssh-keyscan -H "$host" >> /root/.ssh/known_hosts 2>/dev/null || true
done
chmod 600 /root/.ssh/known_hosts 2>/dev/null || true

if [ -f "/etc/ssh-keys/id_ed25519" ]; then
    echo "🔑 Found SSH deploy key (id_ed25519). Installing with 0600 permissions..."
    cp /etc/ssh-keys/id_ed25519 /root/.ssh/id_ed25519
    chmod 600 /root/.ssh/id_ed25519
    [ -f "/etc/ssh-keys/id_ed25519.pub" ] && cp /etc/ssh-keys/id_ed25519.pub /root/.ssh/id_ed25519.pub
elif [ -f "/etc/ssh-keys/id_rsa" ]; then
    echo "🔑 Found SSH deploy key (id_rsa). Installing with 0600 permissions..."
    cp /etc/ssh-keys/id_rsa /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
    [ -f "/etc/ssh-keys/id_rsa.pub" ] && cp /etc/ssh-keys/id_rsa.pub /root/.ssh/id_rsa.pub
else
    echo "ℹ️ Note: No SSH deploy key found at /etc/ssh-keys/. Running in restricted mode (no SSH push)."
fi

# 2. Install / update Git safety hooks (pre-push, pre-commit)
mkdir -p /etc/git-hooks
if [ -d "/etc/itsaplan-runner/git-hooks" ]; then
    cp -f /etc/itsaplan-runner/git-hooks/* /etc/git-hooks/ 2>/dev/null || true
fi
chmod +x /etc/git-hooks/* 2>/dev/null || true
git config --system core.hooksPath /etc/git-hooks
echo "🛡️ Git safety hooks active in /etc/git-hooks"

# 3. Verify @itsaplan/runner version (auto-upgrade if RUNNER_VERSION overrides baked version)
CURRENT_RUNNER_VER="$(npm list -g @itsaplan/runner --depth=0 2>/dev/null | sed -n 's/.*@itsaplan\/runner@\([0-9.]*\).*/\1/p')"
if [ -n "${RUNNER_VERSION:-}" ] && [ "$CURRENT_RUNNER_VER" != "$RUNNER_VERSION" ]; then
    echo "⬆️ Updating @itsaplan/runner from ${CURRENT_RUNNER_VER:-unknown} to ${RUNNER_VERSION}..."
    npm install -g "@itsaplan/runner@${RUNNER_VERSION}"
    CURRENT_RUNNER_VER="$RUNNER_VERSION"
fi
echo "📦 @itsaplan/runner version: ${CURRENT_RUNNER_VER:-unknown}"
echo "🤖 Antigravity CLI version: $(agy --version 2>/dev/null || echo 'unknown')"

# 4. Resolve runner configuration (supports direct .json or .json.tmpl with envsubst)
CONFIG_FILE="${ITSAPLAN_RUNNER_CONFIG:-/etc/itsaplan-runner/itsaplan-runner.json}"
if [ ! -f "$CONFIG_FILE" ] && [ -f "${CONFIG_FILE}.tmpl" ]; then
    echo "🔧 Rendering runner config template ${CONFIG_FILE}.tmpl via envsubst..."
    envsubst < "${CONFIG_FILE}.tmpl" > /tmp/itsaplan-runner.json
    chmod 600 /tmp/itsaplan-runner.json
    CONFIG_FILE="/tmp/itsaplan-runner.json"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: Config file not found at $CONFIG_FILE"
    exit 1
fi
if grep -q "<ITSAPLAN_API_KEY_" "$CONFIG_FILE"; then
    echo "❌ Error: $CONFIG_FILE still contains <ITSAPLAN_API_KEY_...> placeholders."
    exit 1
fi
echo "📋 Using config: $CONFIG_FILE"

# 5. Synchronize MCP server configuration into Antigravity
MCP_SOURCE="${ITSAPLAN_MCP_CONFIG:-/etc/itsaplan-runner/mcp_config.json}"
if [ -f "$MCP_SOURCE" ]; then
    echo "⚙️ Syncing MCP config ($MCP_SOURCE) to /root/.gemini/..."
    mkdir -p /root/.gemini/config /root/.gemini/antigravity
    cp -f "$MCP_SOURCE" /root/.gemini/config/mcp_config.json
    cp -f "$MCP_SOURCE" /root/.gemini/antigravity/mcp_config.json
fi

# 6. Execute project-specific extension hooks in /entrypoint.d/*.sh
if [ -d "/entrypoint.d" ]; then
    for hook in /entrypoint.d/*.sh; do
        if [ -f "$hook" ]; then
            echo "🔌 Running entrypoint extension: $(basename "$hook")..."
            # shellcheck disable=SC1090
            source "$hook"
        fi
    done
fi

# 7. Launch runner
exec itsaplan-runner "$CONFIG_FILE"
