# ADR 023: Immich Machine Learning on OpenVINO

## Status

Accepted — 2026-09-08

## Context

While investigating the Immich outage described in
[[022-intel-gpu-plugin-watchdog]], the machine-learning deployment turned out to
be misconfigured in a way that cost availability without buying anything.

`workload/helm_values/immich.yaml` requested a GPU share for the ML container:

```yaml
image:
  repository: ghcr.io/immich-app/immich-machine-learning
  tag: release
resources:
  requests: { gpu.intel.com/i915: 1 }
  limits:   { gpu.intel.com/i915: 1 }
```

The `release` tag is the **CPU-only** build. It ignores the GPU entirely, so the
i915 share was consumed and never used. The cost was real: the request is a hard
scheduling and admission constraint, so the ML pod shared every failure mode of
the GPU device plugin — for no acceleration in return.

Two facts checked on the running pod before deciding:

- the container runs as `uid=0(root)` with no `securityContext` from the chart;
- `/dev/dri/renderD128` is already injected by the device plugin and is
  world-writable (`crw-rw-rw-`).

So the OpenVINO build needs no extra privileges, device mounts, or
`supplementalGroups` in this cluster. The `release-openvino` tag was confirmed
present in ghcr (manifest `200`).

## Decision

Switch the ML container to the OpenVINO build so that the GPU share it holds is
actually used:

```yaml
image:
  repository: ghcr.io/immich-app/immich-machine-learning
  tag: release-openvino
resources:
  limits:
    memory: 3Gi
```

The memory limit goes from `2Gi` to `3Gi`. The OpenVINO runtime plus its models
need more headroom than the CPU build, and an OOMKill here would reproduce the
exact user-visible symptom this work set out to remove.

The `gpu.intel.com/i915: 1` request stays — it is now load-bearing.

## Consequences

- Smart search and face detection run on the Intel iGPU instead of the CPU.
- First rollout is slow: the OpenVINO image is significantly larger and the
  models are re-fetched for the new runtime.
- If OpenVINO fails to claim the iGPU it silently falls back to CPU. The
  deployment stays up, so the failure is invisible unless the ML logs are checked
  for the active execution provider.
- The ML pod keeps its hard dependency on a healthy device plugin. That risk is
  now mitigated by the watchdog in [[022-intel-gpu-plugin-watchdog]] rather than
  by dropping the GPU request.

## Related

- [[022-intel-gpu-plugin-watchdog]] - Keeping the i915 devices available
- [[008-cloudnativepg-migration]] - Immich database backing store
