# 017 S3 Replication to QNAP

**Date:** 2026-08-06
**Status:** Accepted

## Context
With the migration to a local MinIO instance (see [[016-migrate-to-local-minio]]), we needed a highly available and reliable backup strategy to sync our application data (both files and SQLite databases managed by Litestream) to our QNAP NAS.

Initially, we explored:
1.  **CSI Rclone Union:** Using the Rclone `union` backend to write simultaneously to MinIO and QNAP. This was rejected because the `union` backend acts like RAID0 for writes—if the QNAP is down, the entire write operation fails, creating a single point of failure (SPOF).
2.  **Litestream Multi-Replica:** Using Litestream to natively stream SQLite changes to multiple destinations. This was rejected because recent versions of Litestream explicitly removed support for multiple replicas on a single database to reduce complexity and improve stability.

## Decision
We decided to adopt an asynchronous replication strategy using a Kubernetes `CronJob` powered by `rclone`.

1.  **Single Source of Truth:** All applications (CSI Rclone for files, Litestream for SQLite databases) write exclusively to the highly available local MinIO instance.
2.  **Asynchronous Replication:** A background `CronJob` (`qnap-sync`), deployed via `app-template`, runs every 15 minutes. It executes `rclone sync` to mirror the entire `kms-lab-data` bucket from MinIO to the QNAP NAS.
3.  **Shared Credentials:** We use a centralized Kubernetes Secret (`litestream-s3`) that securely provides credentials for both MinIO and QNAP via Bitwarden.

## Consequences
-   **Pros:**
    - No SPOF for application writes. If the QNAP NAS goes offline, the applications continue to function normally.
    - Simplified Litestream and CSI configurations.
    - True mirroring of all S3 data (databases and files) in one automated step.
-   **Cons:**
    - The QNAP backup can be up to 15 minutes behind the primary MinIO storage. In a catastrophic failure of the local cluster, up to 15 minutes of data could be lost.
