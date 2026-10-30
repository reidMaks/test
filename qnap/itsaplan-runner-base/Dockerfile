# ==============================================================================
# Base Dockerfile: It's a Plan AI Agent Runner (ARM64 / Multi-Arch)
# Shared foundation image for all project-specific agent runners on TV-Box / K8s.
# Provides Node 22, Git, SSH, Antigravity CLI (agy), @itsaplan/runner,
# universal Git safety hooks, and /entrypoint.d/* extension hooks.
# ==============================================================================

FROM node:22-bookworm-slim

LABEL maintainer="Max Infrastructure (IaaC)"
LABEL description="Base autonomous AI Agent runner image for It's a Plan issue tracker"

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.local/bin:/root/.cargo/bin:$PATH"
ENV ITSAPLAN_RUNNER_CONFIG="/etc/itsaplan-runner/itsaplan-runner.json"
ENV DOCKER_CONTAINER=true
ENV ALLOW_DANGEROUS=true

# 1. Install base system utilities, git, ssh, jq, and envsubst (gettext-base)
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    gettext-base \
    git \
    jq \
    libatomic1 \
    openssh-client \
    procps \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Antigravity CLI (agy) via official bootstrapper (auto-detects ARM64/AMD64)
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# 3. Install @itsaplan/runner (version-pinned) and base MCP bridges globally via npm
# renovate: datasource=npm depName=@itsaplan/runner
ARG RUNNER_VERSION=0.7.0
ENV RUNNER_VERSION=${RUNNER_VERSION}
RUN npm install -g \
    "@itsaplan/runner@${RUNNER_VERSION}" \
    mcp-remote \
    mcp-searxng \
    && npm cache clean --force

# 4. Pre-configure SSH known_hosts and global Git safety defaults
RUN mkdir -p /root/.ssh /etc/git-hooks /entrypoint.d && \
    ssh-keyscan -H github.com >> /root/.ssh/known_hosts 2>/dev/null || true && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/known_hosts && \
    git config --global --add safe.directory "*" && \
    git config --global user.name "AI Agent" && \
    git config --global user.email "agent@kms-lab.in.ua" && \
    git config --system core.hooksPath /etc/git-hooks

WORKDIR /workspace

COPY git-hooks/ /etc/git-hooks/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /etc/git-hooks/*

ENTRYPOINT ["/entrypoint.sh"]
