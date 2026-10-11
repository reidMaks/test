# ADR 004: QNAP NAS and Media Stack

## Context
In addition to the main Talos Kubernetes cluster, a separate QNAP NAS operates within the home network. Although not part of the core K8s cluster, it plays a vital role in storage and media streaming.

## Decision
- **Platform**: Docker Compose running directly on the QNAP NAS. Managed via `qnap/` directory.
- **Routing**: A standalone instance of **Traefik** (`traefik-qnap`) handles ingress for the NAS. It routes `*.home.arpa` internal domains and proxies specific services like Proxmox (`pve.kms-lab.in.ua`).
- **Workloads**: The NAS hosts the entire "arr" media stack:
  - `qbittorrent`
  - `prowlarr`, `sonarr`, `radarr`, `lidarr`
  - `seerr`, `cross-seed`
  - `jellyfin` (Media Server)
  - `portainer` (Container Management)
- **Cross-Seed Integrity & Hardlink Safety**:
  - `cross-seed` links files to `/torrent/cross-seed` using `hardlink`.
  - To prevent partial piece mismatches (e.g. tracker-specific MKV headers or metadata) from corrupting shared hardlinks through peer redownloads:
    - `matchMode: "safe"` (strict file matching).
    - `skipRecheck: false` (torrents are injected paused, verified against data blocks, and only resumed if 100% matched).
    - `autoResumeMaxDownload: 0` (disallow resuming torrents with incomplete pieces).
- **Volumes**: Data is stored directly on the NAS native shares (e.g. `/share/CACHEDEV1_DATA/torrent` and `/share/CACHEDEV2_DATA/appdata/`).

## Consequences
- **Pros**: Offloads heavy storage I/O (torrents, media) from the Kubernetes cluster. Utilizes native QNAP capabilities and isolates media traffic. Safe cross-seeding eliminates data corruption risks across hardlinked releases.
- **Cons**: Requires separate management (Docker Compose/Portainer) outside of the main Terraform Kubernetes workflow.
