# Infrastructure Architecture Index

This is the central knowledge base for the Hybrid Talos Kubernetes infrastructure.
All documentation here should be maintained in English and linked using Obsidian-style links.

## Core Topology
- [[Network-Topology]]

## Architecture Decision Records (ADRs)
- [[001-hybrid-cluster]] - Hybrid Talos Kubernetes Cluster (Proxmox + OCI)
- [[002-networking-and-ingress]] - Networking, Ingress, WG Hub, and Cloudflare
- [[003-storage]] - Longhorn Storage and S3 Backups
- [[004-qnap-nas]] - QNAP NAS and Media Stack (Arr-stack)
- [[005-qnap-internal-dns]] - QNAP Internal DNS and Traefik Aliasing
- [[006-qnap-local-ca-tls]] - QNAP Local CA and TLS Configuration
- [[007-freelingo-localization-and-secrets]] - FreeLingo Localization and Secrets Management

## Workloads & Services
- Traefik (Ingress)
- MetalLB (LoadBalancer)
- Longhorn (Storage)
- Cloudflared (Tunnels)
- WireGuard Hub
- QNAP NAS (Jellyfin, Arr-stack, Portainer)
- FreeLingo (AI Language Learning)
