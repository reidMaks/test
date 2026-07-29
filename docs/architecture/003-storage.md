# ADR 003: Storage Strategy

## Context
Stateful workloads require reliable, distributed storage with automated backups.

## Decision
- **Provider**: We use **Longhorn** as the storage class.
- **Data Path**: Mounted to `/var/lib/longhorn` (using explicit mounts on home nodes, and rootfs on OCI nodes).
- **Geo-Replication (Active-Active)**:
  - `defaultClassReplicaCount = 2`.
  - `replicaZoneSoftAntiAffinity = "true"`.
  - With nodes labeled by zone (`topology.kubernetes.io/zone: home` and `oci`), Longhorn automatically places 1 replica on a home node and 1 replica on an OCI node. This provides true geo-redundancy.
- **Backups**: A `RecurringJob` in Kubernetes automatically backs up volumes daily to an S3-compatible storage bucket.
- **Secrets**: S3 credentials (and all other secrets) are injected dynamically via the `bitwarden-secrets` Terraform provider, keeping Git clean.

## Consequences
- **Pros**:
  - Reliable state recovery and high availability.
  - If a home node dies or internet is lost, the OCI Control Plane can reschedule stateful pods to the OCI cloud because a synchronous replica exists there.
- **Cons**:
  - **Latency**: Synchronous replication to OCI introduces 30-50ms latency for every disk write.
  - **Architecture constraints**: Failover to OCI only works for pods that support ARM64.
  - **Split-Brain Risk**: If home internet drops, local pods keep running and writing to the home replica. OCI API server forces a failover (`nodeDownPodDeletionPolicy = "delete-pod-when-node-down"`), spinning up a new pod writing to the OCI replica. When the network returns, data written locally during the outage will likely be overwritten by the OCI state.
