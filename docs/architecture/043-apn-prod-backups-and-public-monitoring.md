# 043 Production Backups (30-Day Retention) & Public Internet Monitoring for APN (`apn-prod`)

**Status:** Accepted (IAAC-5)
**Date:** 2026-10-30
**Related Docs:** [[003-storage]], [[010-gatus-auto-discovery]], [[017-s3-replication-qnap]], [[025-apn-public-ingress-and-dns]], [[036-disaster-recovery-runbook]]

## Context

Following the production launch of the **APN** educational platform on **`apn.in.ua`** in the isolated `apn-prod` namespace ([[025-apn-public-ingress-and-dns]]), two operational requirements remained under ticket **IAAC-5**:

1. **Automated 30-Day Backups:** Both stateful PersistentVolumeClaims in `apn-prod` (`apn-prod-mariadb-data` and `apn-prod-wordpress-uploads`) run on the `longhorn` storage class (2 replicas in the `home` zone) and require daily off-cluster backups with a **30-day retention window** replicated to RustFS/MinIO (`s3://kms-lab-data@us-east-1/longhorn-backups`) and mirrored to QNAP NAS (`qnap-sync`).
2. **True Public Internet Monitoring in Gatus:** Because the Gatus pod (`zone: oci`) sets `HTTP_PROXY` / `HTTPS_PROXY` to `http://wg-hub-proxy.wg-hub.svc.cluster.local:3128` (Squid inside `wg-hub` using internal home router DNS `192.168.0.1`) in order to reach `.home.arpa` and internal LAN endpoints over WireGuard, monitoring `https://apn.in.ua/calculator/` without proxy exclusion would route probes through the internal WireGuard Squid proxy rather than testing the external Internet path.

## Architecture & Data Flow

```mermaid
flowchart LR
    subgraph HomeZone["Home Zone (Proxmox Workers)"]
        MariadbPVC[("PVC: apn-prod-mariadb-data<br/>(2Gi Longhorn)")]
        UploadsPVC[("PVC: apn-prod-wordpress-uploads<br/>(5Gi Longhorn)")]
        LHJob["Longhorn RecurringJob<br/>apn-prod-daily-backup<br/>(02:30 UTC, retain=30)"]
    end

    subgraph OCIZone["OCI Zone (talos-cp-oci / talos-cp-oci-2)"]
        RustFS[("RustFS / MinIO S3<br/>s3://kms-lab-data/longhorn-backups")]
        Gatus["Gatus Pod (default)<br/>NO_PROXY: apn.in.ua,.apn.in.ua<br/>dns-resolver: tcp://1.1.1.1:53"]
        Cloudflared["cloudflared Tunnel"]
        Traefik["Traefik Ingress"]
    end

    subgraph PublicNet["Public Internet (Cloudflare Edge)"]
        CFDNS["Cloudflare Public DNS (1.1.1.1)"]
        CFEdge["Cloudflare Edge WAF + TLS<br/>https://apn.in.ua/calculator/"]
    end

    subgraph QNAP["Home QNAP NAS"]
        QuObjects[("QuObjects S3<br/>qnap:kms-lab-data")]
    end

    LHJob -->|Incremental LZ4 Block Backup| MariadbPVC
    LHJob -->|Incremental LZ4 Block Backup| UploadsPVC
    MariadbPVC -->|S3 Put| RustFS
    UploadsPVC -->|S3 Put| RustFS
    RustFS -->|qnap-sync (every 15m)| QuObjects

    Gatus -->|1. Resolve via 1.1.1.1| CFDNS
    Gatus -->|2. Direct HTTPS (Bypass wg-hub-proxy)| CFEdge
    CFEdge -->|3. QUIC Tunnel| Cloudflared
    Cloudflared --> Traefik
```

## Decisions

### 1. Dedicated 30-Day Longhorn RecurringJob (`workload/infrastructure.tf`)
- Created `kubernetes_manifest.longhorn_apn_prod_daily_backup` (`apn-prod-daily-backup` in `longhorn-system`) scheduled at `30 2 * * *` (`02:30 UTC`) with `task = "backup"`, `retain = 30`, `concurrency = 1`, and group `apn-prod-backups`.
- Because Longhorn CSI does not propagate Kubernetes PVC labels to internal `volumes.longhorn.io` custom resources, Terraform looks up `apn-prod-mariadb-data` and `apn-prod-wordpress-uploads` via `data "kubernetes_persistent_volume_claim"` and attaches `"recurring-job-group.longhorn.io/apn-prod-backups" = "enabled"` directly to the underlying Longhorn `Volume` CRs via `kubernetes_labels`.
- **Storage Capacity Impact:** Longhorn stores deduplicated, `lz4`-compressed `2 MiB` blocks in S3. With `apn-prod-mariadb-data` currently using `~210 MiB` and `apn-prod-wordpress-uploads` using static media files, 30 daily restore points consume `~1–3 GiB` in RustFS (`default/minio` has `>32 GiB` free inside the PVC and `>14 GiB` physical free space on `/var` of `talos-cp-oci`), which `qnap-sync` replicates to the multi-terabyte QNAP NAS every 15 minutes.

### 2. True Public Internet Path for Gatus Monitoring (`workload/gatus_config.yaml`, `workload/helm_values/gatus.yaml`, `workload/gatus.tf`)
- **Bypassing WireGuard Squid Proxy (`NO_PROXY`):** Added `apn.in.ua,.apn.in.ua` to `NO_PROXY` in `workload/helm_values/gatus.yaml`. This forces Gatus's Go HTTP client to connect directly from the OCI node's public network interface instead of sending `CONNECT` requests through `wg-hub-proxy.wg-hub.svc.cluster.local:3128`.
- **Public DNS Resolution (`tcp://1.1.1.1:53`):** Configured `client.dns-resolver: "tcp://1.1.1.1:53"` on the `APN Calculator (apn.in.ua)` endpoint (`https://apn.in.ua/calculator/`) in `workload/gatus_config.yaml` with `interval: 1m`, `[STATUS] == 200`, and `ntfy` alerting.
- **Automatic Config Reload (`checksum/config`):** Added a `checksum/config` pod annotation in `workload/gatus.tf` computed from `kubernetes_config_map.gatus_config.data["config.yaml"]` so future edits to `gatus_config.yaml` automatically roll the Gatus deployment.
