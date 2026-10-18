# ADR 033: Media Stack Configuration & Portainer Terraform Management

**Status:** Superseded (Updated 2026-10-18 — migrated to `portainer/portainer` Terraform provider in `qnap/main.tf`)
**Related Docs:** [[004-qnap-nas]], [[039-authentik-sso-idp]]

## Context
As documented in [[004-qnap-nas]], the media workloads (`qbittorrent`, `sonarr`, `radarr`, `prowlarr`, `lidarr`, `bazarr`, `seerr`, `cross-seed`, `jellyfin`) run via Docker Compose on the QNAP NAS.
Previously, an experimental `arr-configurator` container attempted to mount relative paths (`./configurator/configure.py` and `./templates`) inside a Portainer Git stack. Because Portainer runs inside a container and clones Git repositories into its internal `/data/compose/...` volume rather than the QNAP host filesystem, the QNAP Docker daemon mounted empty directories instead of the script, causing `arr-configurator` to exit with code `1` while the live service configurations and SQLite databases in `/share/CACHEDEV2_DATA/appdata/arr-stack/config/*` remained intact and authoritative.

## Decision
1. **Remove `arr-configurator` and Static Config Overwrites (`qnap/portainer/docker-compose.yml`)**:
   - Removed the broken `arr-configurator` service and static config templates so running SQLite databases and live application configurations on `/share/CACHEDEV2_DATA/appdata/arr-stack/config/*` are never overwritten on container restart.
2. **Manage QNAP Portainer & Stacks via Dedicated Terraform State (`qnap/main.tf`)**:
   - Created a standalone Terraform root module in `qnap/` backed by GCS (`prefix = "terraform/state/qnap"`).
   - Uses the official `portainer/portainer` (`~> 2.0`) provider authenticated via Bitwarden Secrets (`7e8d123d-5b32-49e0-b4a3-b4e701249afd`).
   - Manages:
     - `portainer_user.akadmin` & `portainer_settings.this` (Authentik OIDC SSO integration).
     - `portainer_stack.traefik` (`qnap/traefik/docker-compose.yml`).
     - `portainer_stack.arr_suite` (`qnap/portainer/docker-compose.yml`).

## Consequences
- **Pros**:
  - Live media stack databases and inter-service API wiring in `/share/CACHEDEV2_DATA/appdata/arr-stack/config/*` are 100% preserved and safe from accidental template overwrites.
  - Dedicated Terraform state in `qnap/` isolates QNAP availability from the Kubernetes `workload/` pipeline.
- **Cons**:
  - Application-internal settings inside the `*arr` UIs live on the QNAP persistent volume (`/share/CACHEDEV2_DATA/appdata/arr-stack/config`).
