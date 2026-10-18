# 038: Paperless-ngx OCR Concurrency Tuning (OOM Fix)

**Date:** 2026-10-18
**Status:** Accepted
**Related:** [[001-hybrid-cluster]], [[032-in-cluster-mcp-servers]]

## Context

During the consumption of an 8-page scanned PDF (`Сканований документ.pdf`), the `paperless` pod (`ghcr.io/paperless-ngx/paperless-ngx:3.3.2`) in the `default` namespace was terminated with `OOMKilled` (exit code `137`) at its `2Gi` memory limit.

Inspection of the container logs showed that `ocrmypdf` spawned **6 concurrent worker processes** (`Starting processing with 6 workers concurrently`). Because `PAPERLESS_THREADS_PER_WORKER` was unset, Paperless-ngx defaulted to `os.cpu_count()` of the underlying Talos node (`talos-f9o-10o`, 6 vCPUs). Running 6 parallel `tesseract` + `ghostscript` workers alongside `ImageMagick` thumbnail conversion (`convert`) exceeded the `2Gi` memory limit.

## Decision

We explicitly bound OCR concurrency in `workload/helm_values/paperless.yaml`:

```yaml
PAPERLESS_TASK_WORKERS: "1"
PAPERLESS_THREADS_PER_WORKER: "2"
```

## Consequences

- **Positive:** Peak memory usage during multi-page PDF OCR drops by ~2.5–3x, preventing `OOMKilled` container restarts while staying well within the `2Gi` memory limit.
- **Neutral:** Multi-page OCR processes 2 pages concurrently instead of 6, adding only a few seconds to large multi-page scans while preserving node stability.
