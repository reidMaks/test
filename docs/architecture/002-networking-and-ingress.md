# ADR 002: Networking and Ingress Routing

## Context
We need secure access to services from home and remotely, balancing security for critical apps and ease of use for family members.

## Decision
We implement a dual-ingress strategy:

1. **Private Access (Primary/Critical)**:
   - A custom **WireGuard Hub** (`wg_hub.tf`) runs as a pod explicitly on the `talos-cp-oci` node.
   - The home router and personal devices connect to this VPN.
   - It provides internal DNS (via `dnsmasq` resolving `*.kms-lab.in.ua`), direct proxying to Traefik via `socat`, and an egress proxy via `squid`.
2. **Public Access (Non-Critical/Family)**:
   - **Cloudflared Tunnel** is deployed in the cluster to expose specific, less critical services (e.g., `lubelogger`) without opening any ports on the home router.
   - **Infrastructure as Code**: Cloudflare DNS records (CNAMEs pointing to the Tunnel) and A-records for the VPN are fully managed via the `cloudflare` Terraform provider (`workload/cloudflare.tf`).
3. **Internal Routing**:
   - **MetalLB** assigns IP `192.168.0.45` to the **Traefik** ingress controller, which routes traffic to the actual workloads.

## Consequences
- **Pros**: Zero open ports at home. Complete separation of private (VPN-only) and public (Cloudflare) traffic.
- **Cons**: The WG Hub is a single point of failure tied to one OCI node via `node_selector`. If that specific node goes down, the VPN drops until the node recovers.
