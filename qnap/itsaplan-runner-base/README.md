# It's a Plan Agent Runner Base Image (`itsaplan-runner-base`)

Shared multi-arch (`linux/amd64`, `linux/arm64`) foundation image for running autonomous **It's a Plan** AI agents across multiple projects on the dedicated ARM64 TV-Box (`aml-s9xx-box`, `192.168.0.106`, Portainer Endpoint `8`) or in Kubernetes.

## Included in Base Image

- **Runtime:** `node:22-bookworm-slim` + `git`, `curl`, `jq`, `openssh-client`, `envsubst` (`gettext-base`).
- **Agent CLI:** Google Antigravity CLI (`agy`).
- **Runner Daemon:** `@itsaplan/runner` (version-pinned via `ARG RUNNER_VERSION=0.7.0` and tracked by Renovate).
- **Base MCP Bridges:** `mcp-remote`, `mcp-searxng`.
- **Universal Git Safety Guardrails (`/etc/git-hooks`):**
  - `pre-push`: Blocks direct pushes to `main` and `master` across all repositories unless `ALLOW_MAIN_PUSH=1`, then delegates to repository-local `.githooks/pre-push` or `.git/hooks/pre-push`.
  - `pre-commit`: Automatically dispatches to repository-local `.githooks/pre-commit` or `.git/hooks/pre-commit` using `git rev-parse --show-toplevel`.
- **Extensible Entrypoint (`/entrypoint.sh` + `/entrypoint.d/*.sh`):**
  1. Installs SSH deploy keys from `/etc/ssh-keys/` (`0600`) and populates `known_hosts` for `github.com` and `git.kms-lab.in.ua`.
  2. Verifies `@itsaplan/runner` against `RUNNER_VERSION` (supporting instant runtime upgrades via environment variable without rebuilding child images).
  3. Renders `${ITSAPLAN_RUNNER_CONFIG}.tmpl` via `envsubst` when a template is used, allowing secrets (`ITSAPLAN_API_KEY_*`) to be passed via Portainer environment variables.
  4. Syncs `/etc/itsaplan-runner/mcp_config.json` into `/root/.gemini/config/mcp_config.json` and `/root/.gemini/antigravity/mcp_config.json`.
  5. Sources all project-specific setup scripts in `/entrypoint.d/*.sh`.
  6. Executes `itsaplan-runner`.

## Extending in Project Repositories

Projects that need additional language runtimes, CLIs, or MCP servers extend the base image:

```dockerfile
FROM git.kms-lab.in.ua/max/itsaplan-runner-base:0.7.0

# Example: Add project-specific dependencies (Python, uv, gh, Chromium, WordPress MCP)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv chromium chromium-sandbox \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN npm install -g @modelcontextprotocol/server-puppeteer mcp-wordpress

# Optional project-specific entrypoint hook
COPY 10-project-init.sh /entrypoint.d/10-project-init.sh
RUN chmod +x /entrypoint.d/10-project-init.sh
```

Projects that only require `git`, `agy`, and standard HTTP/SSE MCP servers can run `git.kms-lab.in.ua/max/itsaplan-runner-base:0.7.0` directly without a custom `Dockerfile`.
