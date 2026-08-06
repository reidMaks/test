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

## Workloads & Services
- Traefik (Ingress)
- MetalLB (LoadBalancer)
- Longhorn (Storage)
- Cloudflared (Tunnels)
- WireGuard Hub
- QNAP NAS (Jellyfin, Arr-stack, Portainer)
- FreeLingo (AI Language Learning)
- Open WebUI (LLM Chat)
