# ADR 003: Storage Strategy

## Context
Stateful workloads require reliable, distributed storage with automated backups.

## Decision
- **Provider**: We use **Longhorn** as the storage class.
- **Data Path**: Mounted to `/var/lib/longhorn`.
- **Backups**: A `RecurringJob` in Kubernetes automatically backs up volumes daily to an S3-compatible storage bucket.
- **Secrets**: S3 credentials (and all other secrets) are injected dynamically via the `bitwarden-secrets` Terraform provider, keeping Git clean.

## Consequences
- Reliable state recovery. High availability for persistent volumes across the home workers.
