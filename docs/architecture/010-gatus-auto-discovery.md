# ADR 010: Gatus Auto-Discovery via gatus-sidecar

## Status
Accepted

## Context
Our IaaC cluster uses Gatus for uptime monitoring and status pages (`status.kms-lab.in.ua`).
Previously, all monitored services (Paperless, Tandoor, ActualBudget, etc.) were hardcoded in `gatus_config.yaml`.
As the number of workloads grows, statically defining HTTP checks becomes tedious and error-prone. Additionally, some services might be forgotten or misconfigured.

## Decision
We implemented `gatus-sidecar` inside the Gatus Pod to automatically discover Kubernetes `Ingress` and `Service` resources.
The sidecar scans the `default` namespace (and other specified ones) and dynamically generates a `endpoints.yaml` file containing the monitoring targets.

1. **Auto-Discovery Configuration:**
   - The sidecar container runs alongside Gatus.
   - It is configured with `--auto-service` and `--auto-ingress` arguments to discover `Service` (generates TCP checks) and `Ingress` (generates HTTP checks) resources.
   - It outputs the generated configuration to `/config/endpoints.yaml`.

2. **Gatus Configuration Merging:**
   - Gatus v5.x expects a single configuration path (`GATUS_CONFIG_PATH`). It does not support comma-separated file lists.
   - We mount an `emptyDir` volume at `/config` for Gatus and the sidecar.
   - An `initContainer` copies the statically defined configuration (from `gatus-config` ConfigMap, which includes alerts and external infrastructure checks) into `/config/config.yaml`.
   - When Gatus starts, it reads all `.yaml` files in `/config`, successfully merging the static alerts/external checks with the dynamically generated cluster endpoints.

3. **RBAC:**
   - A `Role` and `RoleBinding` are granted to the Gatus `ServiceAccount` to allow it to read and watch `services` and `ingresses`.

4. **Service-Specific Annotations:**
   - Services that return non-200 HTTP statuses (e.g., Tandoor returns `302 Found` for unauthenticated requests) are annotated on their `Ingress` with `gatus.io/status: "[STATUS] == 200 || [STATUS] == 302"` so Gatus considers them healthy.

## Consequences
- **Positive:** We no longer need to manually add internal cluster services to the Gatus dashboard. It scales automatically.
- **Positive:** Static checks are restricted only to external home infrastructure (Proxmox, NAS, Portainer).
- **Negative:** Gatus sidecar requires elevated RBAC permissions (`get/list/watch` on `services` and `ingresses`) within the monitored namespaces.
