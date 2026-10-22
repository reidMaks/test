# Infrastructure Architecture Index

This is the central knowledge base for the Hybrid Talos Kubernetes infrastructure.
All documentation here should be maintained in English and linked using Obsidian-style links.

## Core Topology
- [[Network-Topology]]

## Architecture Decision Records (ADRs)
- [[001-hybrid-cluster]] - Hybrid Talos Kubernetes Cluster (Proxmox + OCI)
- [[002-networking-and-ingress]] - Networking, Ingress, WG Hub, and Cloudflare
## 🗄️ Storage Architecture
- [[003-storage]] - Distributed block storage (Longhorn)
- [[004-qnap-nas]] - External NAS Integration via NFS
- [[016-migrate-to-local-minio]] - Local MinIO for Litestream & CSI Rclone
- [[017-s3-replication-qnap]] - Asynchronous S3 Replication to QNAP NAS
- [[005-qnap-internal-dns]] - QNAP Internal DNS and Traefik Aliasing
- [[006-qnap-local-ca-tls]] - QNAP Local CA and TLS Configuration
- [[007-freelingo-localization-and-secrets]] - FreeLingo Localization and Secrets Management
- [[008-cloudnativepg-migration]] - ADR: CloudNativePG Migration and Storage Optimization
- [[009-litestream-sqlite-integration]] - Litestream & SQLite Integration
- [[010-gatus-auto-discovery]] - Auto-discovery of Services and Ingresses for Gatus observability.
- [[011-descheduler-tuning]] - Descheduler Tuning and Threshold Optimization
- [[012-add-open-webui]] - Add Open WebUI
- [[013-centralized-grafana-dashboards]] - Centralized Grafana Dashboards and Redis Monitoring
- [[014-mcp-tool-server]] - MCP Tool Server for Open WebUI
- [[015-open-webui-pgvector-rag]] - Open WebUI RAG Architecture (PGVector & OIKB)
- [[016-add-litellm-proxy]] - LiteLLM Proxy for Cost Routing
- [[018-add-headroom-proxy]] - Headroom Context-Compression Proxy for Claude Code & LiteLLM
- [[019-cnpg-memory-limits]] - CNPG Memory Limits and PostgreSQL Tuning (OOM fix)
- [[020-mqtt-broker]] - Edge Mosquitto for the HTRAM CO2 monitor (decommissioned and removed in IAAC-9; protocol analysis retained)
- [[021-esphome-home-zone-pinning]] - Pin ESPHome to the `home` zone so mDNS device discovery works
- [[022-intel-gpu-plugin-watchdog]] - External liveness check for the Intel GPU device plugin (4.5-day Immich outage)
- [[023-immich-openvino-ml]] - Immich ML on the Intel iGPU via the OpenVINO build
- [[024-itsaplan-ai-issue-tracker]] - Deploy "It's a Plan" AI-native issue tracker and MCP server
- [[025-apn-public-ingress-and-dns]] - Production Public Ingress, TLS, and DNS for APN Educational Platform
- [[026-keel-image-automation]] - Automated Workload Updates via Keel (superseded by [[034-renovate-gitops-updates]])
- [[027-apn-pr-preview-and-ci-runner]] - Self-Hosted GitHub Actions Runner & Ephemeral PR Preview Pods for APN
- [[028-mailpit-email-testing]] - Mailpit SMTP Catcher and Email Testing Service
- [[029-apn-performance-optimization-redis-mariadb]] - APN Performance Optimization: Persistent Object Cache & MariaDB Tuning
- [[030-apn-environment-segregation-and-symlinks]] - APN Environment Segregation and Hybrid Symlink Realignment
- [[031-pin-apn-staging-preview-runners-to-home-zone]] - Pin APN Staging, Preview, and CI Runners to Home Zone
- [[032-in-cluster-mcp-servers]] - In-Cluster Remote MCP Servers for Network AI Agents
- [[033-media-stack-configuration-as-code]] - Media Stack Configuration as Code & Auto-Wiring
- [[034-renovate-gitops-updates]] - Declarative Dependency & Image Updates via Renovate Bot (replaces Keel & Diun)
- [[035-hybrid-zone-workload-policy]] - Hybrid Zone Workload Placement Policy (`oci` Always-On Public Tier vs `home` Private/Heavy Tier)
- [[036-disaster-recovery-runbook]] - Disaster Recovery (DR) & 3-2-1 Backup Restore Runbook (MinIO, QNAP NAS, Encrypted Google Drive)
- [[037-rustfs-and-valkey-migration]] - Drop-in Migration: MinIO to RustFS 1.0 and Redis to Valkey 8 (IAAC-24)
- [[038-paperless-ocr-concurrency-tuning]] - Paperless-ngx OCR Concurrency Tuning (OOM Fix)
- [[039-authentik-sso-idp]] - Self-Hosted SSO & Identity Provider (Authentik)
- [[040-forgejo-git-and-container-registry]] - Self-Hosted Forgejo (Git Server, OCI Container Registry & Global CI Runner)
- [[041-holos-tts-migration]] - Ukrainian TTS Migration: Wyoming Piper to HolosTTS (`ha-holos-tts`)

## Workloads & Services
- Traefik (Ingress)
- Authentik (Self-Hosted SSO & Application Portal)
- Forgejo (Self-Hosted Git, OCI Container Registry & Global Actions Runner)
- MetalLB (LoadBalancer)
- Renovate Bot (Declarative GitOps Dependency & Image Updates — replaced Keel & Diun)
- GitHub Actions CI Runner (APN PR Previews & E2E)
- Mailpit (SMTP Catcher & Email Testing)
- Longhorn (Storage)
- Cloudflared (Tunnels)
- WireGuard Hub
- QNAP NAS (Jellyfin, Arr-stack, Portainer)
- FreeLingo (AI Language Learning)
- Open WebUI (LLM Chat)
- HolosTTS (Ukrainian TTS — Wyoming TCP:10200 & OpenAI HTTP:8000 on `192.168.0.47`)
- It's a Plan (AI-Native Issue Tracker)
- APN (Educational Platform - WordPress, MariaDB, TutorLMS)
- Shopping Master (Telegram Bot & Mini App WebApp on `shopping.kms-lab.in.ua` -> TV-Box `192.168.0.106:8080`)
- In-Cluster MCP Servers (Kubernetes & Tool Servers for Network Agents)
