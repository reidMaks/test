# 011 - Descheduler Tuning

## Context
The cluster uses Kubernetes Descheduler to maintain workload distribution across local nodes (Proxmox) and cloud nodes (OCI).
1. **Initial configuration (`100` deviation):** The `LowNodeUtilization` strategy was originally configured with `useDeviationThresholds = true` and `100` as the threshold for both `thresholds` and `targetThresholds`, which effectively disabled evictions.
2. **Second iteration (`20` deviation) & `pods` threshold pitfall (2026-10 Audit):** Updating `thresholds` and `targetThresholds` to `20` with `useDeviationThresholds = true` still resulted in `0` evictions (`Number of underutilized nodes: 0`). In Kubernetes Descheduler, a node is classified as *underutilized* only when **all** configured resources (`cpu`, `memory`, `pods`) fall below `average - threshold`. Because the cluster-wide average pod count was `~26.55%` (of 110 max pods), subtracting `20%` required a node to have `< 6.55%` pods (`~7.2` pods) to be considered underutilized. However, every node runs at least 10 DaemonSet pods (`~9.1%`), making it mathematically impossible for any node (such as `talos-f9o-10o` at 17 pods / `15%`, `28%` CPU, `12%` RAM) to be recognized as a target for receiving evicted pods.
3. **CronJob self-inflation:** The Descheduler CronJob requested `500m` CPU and `256Mi` RAM by default, artificially inflating CPU request utilization on whichever node ran the CronJob every 15 minutes.

## Decision
1. **Switch to explicit absolute thresholds (`useDeviationThresholds = false`):**
   - `thresholds = { cpu = 35, memory = 35, pods = 50 }`: Any node with `<= 35%` CPU, `<= 35%` Memory, and `<= 50%` Pods (up to 55 pods) is classified as **underutilized** (immediately qualifying `talos-f9o-10o`).
   - `targetThresholds = { cpu = 65, memory = 65, pods = 75 }`: Any node exceeding `65%` CPU or `65%` Memory (or `75%` Pods) is classified as **overutilized**.
2. **Right-size CronJob resources & history:** Lowered CronJob requests to `cpu = 50m`, `memory = 64Mi` (limit `128Mi`) and set `successfulJobsHistoryLimit = 1` and `failedJobsHistoryLimit = 1`.

## Consequences
- `talos-f9o-10o` is properly recognized as underutilized, allowing Descheduler to evict pods from overloaded nodes (`talos-cp-oci-2` at 89% CPU, `talos-cp-oci` at 69% CPU / 67% RAM, and `talos-wfh-33w` at 69% RAM) and rebalance the cluster.
- The Descheduler CronJob no longer skews node CPU allocation metrics during its execution window.
