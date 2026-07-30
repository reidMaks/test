# 008 ADR: CloudNativePG Migration and Storage Optimization

## Status
**Implemented** (July 2026)

## Context
The current Kubernetes cluster topology spans a hybrid environment: local Proxmox nodes (amd64) and Oracle Cloud Infrastructure (OCI) instances (arm64).

Currently, persistent storage is provided by **Longhorn**, which is configured as a geo-distributed block storage solution across these nodes. When stateful services (such as Postgres and Redis for apps like FreeLingo, Paperless, and Tandoor) write data, Longhorn replicates these blocks synchronously over the network (including the WAN link between the home lab and OCI).

Furthermore, the cluster utilizes a **Database-per-service** model. Each application spins up its own isolated PostgreSQL and Redis instances.

### Problems with the Current Approach:
1. **Resource Overhead (RAM/CPU):** Running multiple independent PostgreSQL instances consumes a significant amount of RAM on the local `amd64` nodes. A single Proxmox worker node (`talos-f9o-10o`) is already sitting at 84% memory utilization.
2. **Synchronous WAN Replication (Latency):** Longhorn's synchronous replication means that local database writes must wait for acknowledgment from the OCI cloud replicas. This introduces WAN latency into every block write, significantly degrading database I/O performance.
3. **Storage Fragmentation:** Multiple PVCs exist for different Postgres instances, leading to storage fragmentation and management overhead.

## Proposed Architecture

To optimize both compute and storage architectures for the hybrid cluster, we propose transitioning from the Database-per-service model to a **Database-as-a-Service (DBaaS)** model using [CloudNativePG (CNPG)](https://cloudnative-pg.io/).

### 1. Unified Database Cluster
Instead of deploying PostgreSQL via Helm charts for every application, we will deploy a single, robust CloudNativePG cluster.
- Each application (FreeLingo, Paperless, Tandoor) will be assigned its own logical database and user credentials within this shared cluster.
- **Benefit:** Massive RAM savings by eliminating redundant PostgreSQL background processes.

### 2. Disentangling Storage Replication from WAN
With CNPG, we can leverage application-level (PostgreSQL) replication instead of block-level (Longhorn) replication for disaster recovery.
- **Longhorn Optimization:** We will pin Longhorn strictly to the local `amd64` Proxmox nodes (`kubernetes.io/arch: amd64`). Longhorn will only replicate data over the fast Local Area Network (LAN).
- **Database HA across WAN:** We will configure CNPG to use asynchronous streaming replication to a standby node located in OCI (`arm64`). PostgreSQL handles WAN latency gracefully without blocking primary node writes.
- **Benefit:** Disk I/O performance on the local nodes will drastically improve, as writes no longer block waiting for OCI acknowledgments.

### 3. Ephemeral Redis
For applications utilizing Redis solely as a cache or Celery broker (e.g., FreeLingo), we will replace Longhorn PersistentVolumeClaims (PVCs) with `emptyDir` (ephemeral node storage or RAM).
- **Benefit:** Prevents Longhorn from thrashing disks and network bandwidth with constant, high-frequency cache writes.

## Migration Strategy
The following steps were executed to migrate to the new architecture:
1. Deployed CloudNativePG operator (`cnpg-system`) and initialized the `shared-db` cluster.
2. Created logical databases and owners via `initdb` configuration in `cnpg.tf`.
3. Reconfigured Tandoor, Paperless, and FreeLingo workloads to use `shared-db-rw` service.
4. Manually removed the old Postgres StatefulSets and associated Longhorn PVCs (including cleanup of orphaned `Released` Longhorn PVs/Volumes).

## Implementation Details

### High Availability and Pod Anti-Affinity
The CNPG cluster was configured with `instances: 3` to ensure high availability.
To guarantee cross-site disaster recovery (home lab + OCI cloud), we enforced a strict scheduling policy:
```hcl
podAntiAffinityType = "required"
```
Because the home lab only has 2 physical `amd64` nodes (`talos-f9o-10o`, `talos-wfh-33w`), Kubernetes is forced to schedule the 3rd replica on the remaining OCI nodes (`arm64`), despite the CNPG primary preferring `amd64`. This setup effectively achieves:
- **Primary / Replica 1 (Local):** Fast, low-latency synchronous reads/writes.
- **Replica 2 (Cloud):** Asynchronous streaming replica in OCI, resilient to home power/internet outages.

### Monitoring
CNPG was integrated into the cluster's Grafana and VictoriaMetrics stack:
- **ServiceMonitor/VMPodScrape:** Added `VMPodScrape` resources for the operator and the cluster pods to scrape metrics via port `9187`.
- **Grafana Dashboard:** Configured a `ConfigMap` labeled with `grafana_dashboard=1` containing the official CNPG dashboard JSON, allowing the Grafana Sidecar (`grafana-sc-dashboard`) to automatically discover and mount it.
