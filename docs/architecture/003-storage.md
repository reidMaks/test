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
  - **Split-Brain Mitigation (Network Fencing)**: In a typical setup, a split-brain would occur if local pods kept receiving writes while OCI failed over. However, this is naturally mitigated by the home router's DNS configuration. The router forces all `*.kms-lab.in.ua` traffic through `10.9.0.1` (the WG Hub in OCI). If the internet drops, local users cannot reach the services locally. This acts as a perfect "Kill-switch", preventing local writes during an outage and allowing the OCI replica to safely take over without data conflicts.
