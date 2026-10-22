# ADR 033: Media Stack Configuration & Portainer Terraform Management

**Status:** Superseded (Updated 2026-10-18 — migrated to `portainer/portainer` Terraform provider in `qnap/main.tf`)
**Related Docs:** [[004-qnap-nas]], [[039-authentik-sso-idp]]

## Context
As documented in [[004-qnap-nas]], the media workloads (`qbittorrent`, `sonarr`, `radarr`, `prowlarr`, `lidarr`, `bazarr`, `seerr`, `cross-seed`, `jellyfin`) run via Docker Compose on the QNAP NAS.
Previously, an experimental `arr-configurator` container attempted to mount relative paths (`./configurator/configure.py` and `./templates`) inside a Portainer Git stack. Because Portainer runs inside a container and clones Git repositories into its internal `/data/compose/...` volume rather than the QNAP host filesystem, the QNAP Docker daemon mounted empty directories instead of the script, causing `arr-configurator` to exit with code `1` while the live service configurations and SQLite databases in `/share/CACHEDEV2_DATA/appdata/arr-stack/config/*` remained intact and authoritative.

## Decision
1. **Remove `arr-configurator` and Static Config Overwrites (`qnap/portainer/docker-compose.yml`)**:
   - Removed the broken `arr-configurator` service and static config templates so running SQLite databases and live application configurations on `/share/CACHEDEV2_DATA/appdata/arr-stack/config/*` are never overwritten on container restart.
2. **Manage QNAP Portainer & Stacks Directly via Dedicated Terraform State (`qnap/main.tf`)**:
   - Created a standalone Terraform root module in `qnap/` backed by GCS (`prefix = "terraform/state/qnap"`).
   - Uses the official `portainer/portainer` (`~> 2.0`) provider connecting directly to `https://192.168.0.21:9443` (so `traefik` stack updates never interrupt Terraform API calls) and authenticated via Bitwarden Secrets (`7e8d123d-5b32-49e0-b4a3-b4e701249afd`).
   - Manages:
     - `portainer_user.akadmin` & `portainer_settings.this` (Authentik OIDC SSO integration).
     - `portainer_stack.traefik` (`method = "string"`, `stack_file_content = file("${path.module}/traefik/docker-compose.yml")`).
     - `portainer_stack.arr_suite` (`method = "string"`, `stack_file_content = file("${path.module}/portainer/docker-compose.yml")`).
3. **Declarative `qBittorrent` Tuning & SSO Whitelist via Environment Wrapper (`qnap/portainer/docker-compose.yml`)**:
   - All non-default `qBittorrent` settings are declared as `QBT_*` environment variables in `qnap/portainer/docker-compose.yml` and applied by an `entrypoint` wrapper (`sed` bootstrap on `/config/qBittorrent/qBittorrent.conf` before `/init` plus a background `POST /api/v2/app/setPreferences` call once the WebUI listens on `127.0.0.1:8085`).
   - Key optimizations for QNAP HDD RAID (`CACHEDEV1_DATA`): `DiskIOType=Posix` (`disk_io_type=2` instead of `mmap`), `async_io_threads=4`, `hashing_threads=1`, `file_pool_size=100`, `disk_queue_size=4194304` (4 MiB), `enable_coalesce_read_write=true`, `enable_piece_extent_affinity=true`, `max_connec=500`, `max_uploads=20`, `max_uploads_per_torrent=10`, and `anonymous_mode=false` for private tracker compatibility.
4. **Runtime Memory, Garbage Collector, and `Jellyfin` CPU/Disk Optimization for 4 GB ARM64 NAS (`qnap/portainer/docker-compose.yml`)**:
   - **`.NET` Workloads (`Sonarr`, `Radarr`, `Prowlarr`, `Lidarr`, `Jellyfin`):** Configured `DOTNET_gcServer=0` (Workstation GC), `DOTNET_GCConserveMemory=9`, `MALLOC_TRIM_THRESHOLD_=131072`, and `MALLOC_ARENA_MAX=2` alongside cgroup `mem_limit` (`350m` for `*arr`, `1200m` for `Jellyfin`) so `.NET` sizes its GC heap to container cgroup limits rather than the 4 GB QNAP host RAM.
   - **Declarative `Jellyfin` Configuration (`encoding.xml`, `system.xml`, `network.xml` & `network_mode: host`):** Extracted all non-default transcoding, server, and LAN discovery settings into `JELLYFIN_*` environment variables applied via an `entrypoint` wrapper before `/init`: `EncodingThreadCount=2`, `EnableThrottling=true` (`180s`), `EnableSegmentDeletion=true` (`720s`), `EncoderPreset=superfast`, `LibraryScanFanoutConcurrency=2`, `LibraryMetadataRefreshConcurrency=2`, `ParallelImageEncodingLimit=1`, `EnableKeyFrameOnlyExtraction=true` for Trickplay, and `JELLYFIN_PublishedServerUrl=http://192.168.0.21:8096` (`PublishedServerUriBySubnet` + empty `LocalNetworkAddresses` + `EnableIPv6=false` in `network.xml`). Configured `network_mode: host` on `jellyfin` (with a corresponding file-provider route `jellyfin.home.arpa -> http://192.168.0.21:8096` in `qnap/traefik/docker-compose.yml`) so UDP `7359` broadcast packets (`255.255.255.255` / `192.168.0.255`) reach Jellyfin directly without being dropped by Docker bridge `iptables` (`--dst-type LOCAL`).
   - **Python (`Bazarr`):** Added `PYTHONOPTIMIZE=1`, `MALLOC_TRIM_THRESHOLD_=65536`, `MALLOC_ARENA_MAX=2`, and `mem_limit: 350m`.
   - **Node.js (`Seerr`, `Cross-Seed`):** Switched `Seerr` `LOG_LEVEL` from `debug` to `info` (eliminating continuous disk log writes) and bounded V8 Old Space via `NODE_OPTIONS=--max-old-space-size=160` (`128` for `cross-seed`) with `MALLOC_ARENA_MAX=2`.

## Consequences
- **Pros**:
  - Live media stack databases and inter-service API wiring in `/share/CACHEDEV2_DATA/appdata/arr-stack/config/*` are 100% preserved and safe from accidental template overwrites.
  - Dedicated Terraform state in `qnap/` deploys changes to `qnap/portainer/docker-compose.yml` and `qnap/traefik/docker-compose.yml` immediately on `terraform apply` without relying on Portainer Git polling.
  - `qBittorrent` and the entire `arr-suite` are tuned for low RAM footprint (~450–600 MiB saved on the 4 GB NAS) and minimal HDD seek thrashing.
- **Cons**:
  - Application-internal settings inside the `*arr` SQLite databases live on the QNAP persistent volume (`/share/CACHEDEV2_DATA/appdata/arr-stack/config`).
