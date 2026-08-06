# 016 Migrate S3 Workloads to Local MinIO

**Status:** Applied
**Date:** 2026-08-06

**Context:** Our IaaC stack used Oracle Object Storage (OOS) for Litestream database backups (SQLite) and file attachments via CSI Rclone. However, the continuous sync operations of Litestream and other backups exceeded Oracle Cloud's "Always Free" tier limits for API requests, which led to unexpected billing. While we initially tried to mitigate this by limiting Litestream's `sync-interval` to 10 minutes, the fundamental issue remained.

**Decision:**
1. We deployed a local **MinIO** instance directly in the `workload` module via the `app-template` Helm chart (single-node, StatefulSet).
2. MinIO utilizes local high-performance storage via Longhorn `strict-local` policy (`longhorn-oci-local` StorageClass) to avoid network overhead.
3. We migrated all Litestream replicas (`wishlist-db`, `actualbudget-db`) and Rclone volumes (`actualbudget-files-s3`, `wishlist-uploads-s3`) to MinIO.
4. We decoupled the Terraform state by defining the MinIO endpoint (`http://minio.default.svc.cluster.local:9000`) in `workload/locals.tf` instead of fetching it from `infra`.
5. We removed the `sync-interval: 10m` limit for Litestream, reverting it to the default `1s` for instant backups, as local storage has no request quotas or costs.
6. We configured `VMServiceScrape` for MinIO using the job label `app.kubernetes.io/name=minio` to properly expose its metrics to VictoriaMetrics, which natively integrates with the MinIO Dashboard.

**Consequences:**
- **Zero Cloud Costs:** We eliminated OOS API billing by moving all S3 requests to the local cluster.
- **Real-time Backups:** Litestream database backups are now instantaneous (1-second RPO instead of 10-minute).
- **Decoupled Architecture:** `workload` module is independent of `infra` module outputs, fixing Terraform apply deadlocks during network outages.
- Fast local I/O for SQLite backups via MinIO.
