# ADR 021: Pin ESPHome to the `home` Zone

## Status

Accepted — 2026-09-07

## Context

The ESPHome dashboard (`esphome.kms-lab.in.ua`, `helm_release.esphome` in
`workload/esphome.tf`) reported **every device as offline**, although at least two
ESP nodes were up and talking to Home Assistant.

The pod was scheduled onto `talos-cp-oci` — an Oracle Cloud control-plane node in
the `oci` zone (`10.0.1.140`). The values file already sets `hostNetwork: true`,
but host networking on an OCI node puts the dashboard on the OCI VCN, not on the
home LAN:

```text
$ kubectl exec esphome-… -- cat /proc/net/route
eth0        10.1.0.0/24     # OCI VCN
flannel.1   10.244.x.x      # pod network
# no route to 192.168.0.0/24

$ kubectl exec esphome-… -- ping -c2 192.168.0.120
2 packets transmitted, 0 received, 100% packet loss
```

Two independent failures follow from that placement:

1. **mDNS discovery.** The dashboard resolves `<device>.local` via multicast to
   `224.0.0.251` with `TTL=1`. That traffic is link-local by definition and never
   crosses the WireGuard tunnel between OCI and home.
2. **Unicast fallback.** Even the ping/API fallback fails — the home LAN
   `192.168.0.0/24` is simply not routable from the OCI node (only node-to-node
   KubeSpan addresses are).

The `helm_values/esphome.yaml` file had no placement constraint at all, so the
scheduler was free to pick any node. `hostNetwork` alone is not a placement
constraint — it only decides *which* network namespace is used, not *where*.

## Decision

Pin the ESPHome controller to the home zone, matching the existing pattern used by
`speedtest` (node affinity) and `gatus` (node selector):

```yaml
controllers:
  main:
    pod:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      nodeSelector:
        topology.kubernetes.io/zone: home
```

Nodes carry `topology.kubernetes.io/zone=home` (`talos-b7w-rgq`, `talos-wfh-33w`,
`talos-f9o-10o` on `192.168.0.40-42`) or `topology.kubernetes.io/zone=oci`.

`nodeSelector` is a hard constraint, so the descheduler (see
[[011-descheduler-tuning]]) cannot rebalance the pod back onto OCI.

## Consequences

- The dashboard shares an L2 segment with the ESP devices; mDNS discovery and the
  native API both work, and device status is reported correctly.
- ESPHome compilation runs on an amd64 home node — faster than the OCI arm64 nodes,
  and it no longer cross-compiles on a shared control-plane node.
- Losing all three home nodes leaves ESPHome unschedulable. That is acceptable:
  with the home site down there are no reachable devices to manage anyway.

## Rule of Thumb

**Any workload that must reach LAN devices — mDNS, SSDP, DHCP, broadcast, or plain
`192.168.0.0/24` unicast — needs both `hostNetwork: true` **and** a `home` zone
selector.** See [[020-mqtt-broker]] for the same constraint on the edge broker.

## Related

- [[001-hybrid-cluster]] - Zone layout of the hybrid cluster
- [[011-descheduler-tuning]] - Why a hard constraint is required
- [[020-mqtt-broker]] - Another LAN-adjacent edge workload
