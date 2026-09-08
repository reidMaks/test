# ADR 022: Watchdog for the Intel GPU Device Plugin

## Status

Accepted — 2026-09-08

## Context

Immich was unreachable for roughly 4.5 days (03.09–07.09.2026). The application
itself was healthy; the failure came from the Intel GPU device plugin on
`talos-wfh-33w`, the only node with an Intel iGPU.

Immich requests `gpu.intel.com/i915: 1` as a hard resource in both the `server`
and the `machine-learning` containers (see [[023-immich-openvino-ml]]). When
kubelet has no *healthy* i915 devices, such pods cannot pass admission:

```text
UnexpectedAdmissionError: Allocate failed due to no healthy devices present;
cannot allocate unhealthy devices gpu.intel.com/i915
```

The plugin process never crashed. Its last log line was `03.09 05:51`, after
which it stayed alive and silent until the node restarted it on `07.09 16:35 UTC`
with `exitCode: 255`. For four days the container looked perfectly healthy to
Kubernetes while kubelet saw zero allocatable devices.

Rejected pods stay in phase `Failed` forever, so the namespace also accumulates
ghost pods that never get collected.

### Why not a plain `livenessProbe` on the DaemonSet

Three independent blockers, all verified against the running cluster:

1. **The DaemonSet is not ours.** It carries
   `ownerReferences: [GpuDevicePlugin/gpudeviceplugin-sample, controller: true]`
   and is reconciled by the Intel device plugins operator. The `GpuDevicePlugin`
   CRD exposes only `image`, `initImage`, `logLevel`, `sharedDevNum`,
   `resourceManager`, `enableMonitoring`, `preferredAllocationPolicy`,
   `nodeSelector` and `tolerations` — no probes, no pod-spec passthrough. A
   hand-patched probe is out-of-band state that the operator can revert.
2. **The image is distroless.** `intel/intel-gpu-plugin:0.30.0` has no
   `/bin/sh` (`exec: "/bin/sh": stat /bin/sh: no such file or directory`), so an
   `exec` probe cannot run.
3. **There is nothing to connect to.** The plugin serves only unix sockets under
   `/var/lib/kubelet/device-plugins/` and declares no container ports, so neither
   `httpGet` nor `tcpSocket` has a target.

A probe also could not observe the actual failure: the symptom lives in
*kubelet's* view of device health, not inside the plugin process.

## Decision

Implement the liveness check **outside** the DaemonSet, as a CronJob in
`kube-system` that compares the two views that diverged during the incident:

- what kubelet reports — `.status.allocatable["gpu.intel.com/i915"]` on nodes
  labelled `intel.feature.node.kubernetes.io/gpu=true`;
- whether the plugin pod is actually `Running` on that node.

When allocatable is `0`/absent while the plugin pod has been running longer than
a 300 s grace window, the plugin is hung: the CronJob deletes the pod and the
DaemonSet recreates it. The grace window uses
`.status.containerStatuses[0].state.running.startedAt` — the current container
instance, not the pod, which can be weeks older than the container.

The same job deletes pods in phase `Failed` with reason
`UnexpectedAdmissionError`, which are terminal garbage left behind by any GPU
outage.

Defined in `workload/intel_gpu_plugin.tf`:

| Property | Value |
| --- | --- |
| Schedule | `*/10 * * * *`, `concurrencyPolicy: Forbid` |
| Image | `alpine/k8s:1.36.1` (matches cluster v1.36.1; needs a shell, unlike the distroless official kubectl image) |
| Placement | `topology.kubernetes.io/zone: home` — the GPU node and every i915 consumer live there |
| RBAC | `nodes: get,list`; `pods: get,list,delete` |

## Consequences

- A hung plugin now self-heals within 10 minutes instead of waiting for a node
  reboot. The 4.5-day class of outage is closed.
- Ghost `UnexpectedAdmissionError` pods are cleaned up automatically.
- **`pods/delete` is cluster-wide.** It has to be: the plugin lives in
  `kube-system` while its consumers live in `default`. The job only ever deletes
  pods matching `app=intel-gpu-plugin` or pods already in phase `Failed`.
- **A physically dead GPU produces a restart every 10 minutes.** The watchdog
  cannot distinguish a hung plugin from broken hardware. This is a deliberate
  trade: the churn is bounded, visible in the CronJob logs, and preferable to a
  silent multi-day outage.
- The watchdog does not address the *other* observed failure mode — on kubelet
  restart, pods are re-admitted before the plugin re-registers its devices and
  get rejected. That race is self-healing (the ReplicaSet schedules a
  replacement) and only leaves ghost pods, which this job now removes.

## Verification

The script was extracted from the Terraform heredoc and executed against the live
cluster behind a shim that intercepted every `kubectl delete`:

- healthy state → `node/talos-wfh-33w: i915 allocatable=5, healthy`, no restart;
- simulated `allocatable=0` → correctly identified the plugin pod and the
  13.7 h container age, and would have deleted the pod;
- grace window not elapsed → skipped with `still registering`;
- cleanup selected exactly the four `UnexpectedAdmissionError` pods and correctly
  ignored unrelated `Failed`/`Terminated` pods in `wg-hub`.

## Related

- [[021-esphome-home-zone-pinning]] - The other `home` zone placement constraint
- [[023-immich-openvino-ml]] - Why Immich holds an i915 share at all
- [[011-descheduler-tuning]] - Scheduling behaviour in the hybrid cluster
