# ADR-019: CNPG Memory Limits and PostgreSQL Tuning

## Status
Accepted — 2026-08-30

## Context

On 2026-08-30 at ~06:16 UTC, Proxmox worker node `talos-f9o-10o` (192.168.0.42,
12 GB RAM) went **NotReady** due to OOM.  Root cause analysis:

1. The CNPG `shared-db` Cluster had **no `resources` block** (`resources: {}`),
   giving every PG pod **BestEffort** QoS — no memory limit whatsoever.

2. The `openwebui` database holds a 4.7 GB `document_chunk` table:
   - 238 MB heap
   - 2,380 MB IVFFlat vector index (`idx_document_chunk_vector`)
   - 2,038 MB TOAST (embedding binary data)

3. PostgreSQL defaults (`shared_buffers=128MB`, `effective_cache_size=4GB`)
   caused the OS to page-cache the entire dataset.  Over ~30 days the Linux
   page cache grew monotonically (no cgroup limit → no eviction pressure),
   while co-located pods (Open WebUI 9 Gi limit, Whisper 4 Gi limit) already
   overcommitted the node.

4. The tipping point was reached today — a routine operation (WAL checkpoint,
   autovacuum, or RAG query) needed a few more MB and triggered the Talos OOM
   controller, which repeatedly SIGKILL-ed the PG cgroup.  The kill storm
   cascaded into containerd and kubelet health-check failures, leaving the
   node permanently NotReady until manual reboot.

## Decision

### Container resource limits

```hcl
resources = {
  requests = { memory = "512Mi", cpu = "100m" }
  limits   = { memory = "2Gi" }
}
```

- Moves PG pods from BestEffort to **Burstable** QoS.
- 2 Gi limit caps page-cache growth inside the cgroup.
- 512 Mi request gives the scheduler visibility into actual needs.

### PostgreSQL memory parameters

| Parameter | Old (default) | New | Rationale |
|---|---|---|---|
| `shared_buffers` | 128 MB | 256 MB | Doubles the hot-data buffer within the 2 Gi envelope |
| `work_mem` | 4 MB | 8 MB | Doubles per-sort/hash budget; still safe at 100 connections |
| `effective_cache_size` | 4 GB | 512 MB | Tells planner to prefer index scans over seq scans on large tables |
| `maintenance_work_mem` | 64 MB | 128 MB | Speeds up VACUUM / CREATE INDEX within bounded RAM |

## Consequences

- **Positive:** Node-level OOM is no longer possible from PG alone.  The
  2 Gi cgroup limit means the kernel OOM killer targets only the PG
  container, not kubelet/containerd.
- **Positive:** `effective_cache_size=512MB` steers the planner toward index
  scans on the 2.4 GB IVFFlat index, which is the correct access pattern for
  vector similarity queries.
- **Trade-off:** OS page cache for PG data is now bounded at ~1.5 GB (2 Gi
  minus PG internal allocations).  Repeated cold vector searches over the
  full 4.7 GB dataset may hit disk (Longhorn SSD) more often — latency
  difference is ~10 ms → ~30 ms, imperceptible for a home-lab.

## Related

- [[008-cloudnativepg-migration]]
- [[015-open-webui-pgvector-rag]]
