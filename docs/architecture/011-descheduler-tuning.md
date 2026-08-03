# 011 - Descheduler Tuning

## Context
The cluster uses Kubernetes Descheduler to maintain workload distribution across local nodes (Proxmox) and cloud nodes (OCI). The `LowNodeUtilization` strategy was originally configured with `useDeviationThresholds = true` and `100` as the threshold for both `thresholds` (CPU, Memory, Pods) and `targetThresholds`.
Because this strategy interprets these values as percentage deviations from the mean (with `useDeviationThresholds`), a value of 100 meant a node was considered under-utilized only if its usage was 100% below the average (which is effectively impossible) or over-utilized if it was 100% above. This essentially disabled descheduler evictions as the criteria were practically never met.

## Decision
We updated the thresholds to `20` for both `thresholds` and `targetThresholds` while maintaining `useDeviationThresholds = true`.
This means a node is considered under-utilized if its resource usage is 20% below the cluster average, and over-utilized if it's 20% above the cluster average.

## Consequences
- Descheduler will now actively balance pods by evicting them from nodes that deviate significantly from average usage.
- This results in a much more balanced cluster load across all nodes.
