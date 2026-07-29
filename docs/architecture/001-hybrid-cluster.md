# ADR 001: Hybrid Talos Kubernetes Cluster

## Context
The goal is to maintain a highly available, fault-tolerant, and free (or extremely cheap) Kubernetes infrastructure that survives home internet/power outages.

## Decision
We use a hybrid cluster managed by Talos Linux:
- **Home (Proxmox)**: One Control Plane (`cp_01`) and two Worker nodes (`worker_01`, `worker_02`) on local hardware for heavy lifting.
- **Cloud (OCI)**: Two Control Plane nodes (`talos_oci`, `talos_oci_2`) running on Oracle Cloud Infrastructure (Always Free ARM A1.Flex instances).
- **Network**: Nodes are securely meshed together using Talos **KubeSpan** (built-in WireGuard), ensuring seamless communication between the home NAT environment and the cloud.

## Consequences
- **Pros**: The `etcd` quorum survives even if the home lab goes offline (2 out of 3 CPs are in the cloud). The cluster API remains reachable. Fully free cloud tier.
- **Cons**: Latency between OCI and home requires careful workload scheduling (handled by node labels).
