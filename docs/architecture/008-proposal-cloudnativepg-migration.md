# 008 Proposal: CloudNativePG Migration and Storage Optimization

## Status
Proposed (Future Roadmap)

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
If this proposal is accepted, the migration would follow these steps:
1. Deploy CloudNativePG operator and initialize the shared cluster on Proxmox nodes.
2. Create logical databases for existing services (FreeLingo, Paperless, etc.).
3. Export data from the individual Postgres pods (using `pg_dump`) and import it into the CNPG cluster.
4. Update the Helm `values.yaml` for each service to point to the CNPG cluster.
5. Reconfigure Redis deployments to use `emptyDir`.
6. Remove the old Postgres StatefulSets and delete their associated Longhorn PVCs.
7. Reconfigure Longhorn Node Selectors to evict replicas from OCI nodes.
