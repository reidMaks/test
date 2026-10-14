# 026 Automated Workload Updates via Keel

**Status:** Superseded by [[034-renovate-gitops-updates]] (Decommissioned 2026-10-14)
**Date:** 2026-09-25

> [!WARNING]
> **Decommissioned (2026-10-14):** Both **Keel** (`workload/keel.tf`) and **Diun** (`workload/diun.tf`) have been removed from the cluster and replaced by **Renovate Bot** (`renovate.json`, see [[034-renovate-gitops-updates]]). In-cluster image polling created state drift against Terraform and required elevated cluster-wide RBAC permissions.

## Context

Application container images (such as `ghcr.io/reidmaks/apn:staging`) are built and pushed to GitHub Container Registry (GHCR) via GitHub Actions CI workflows.

In Kubernetes, setting `imagePullPolicy: Always` ensures that new pods pull the latest image upon creation, but Kubernetes does not actively monitor container registries for digest changes on mutable tags (`staging`, `latest`). Without an external trigger or controller, the running pods remain on the old image digest indefinitely until a manual `kubectl rollout restart` is performed.

To achieve hands-off continuous delivery for `apn` (and future applications) without the substantial memory footprint of full GitOps suites like ArgoCD, we originally deployed **Keel** as an in-cluster image update operator.

## Architecture & Topology (Historical)

```mermaid
flowchart TD
    subgraph CI["GitHub Actions CI"]
        GHA["GitHub Actions Workflow<br/>(build-image.yml)"]
    end

    subgraph Registry["GitHub Container Registry"]
        GHCR["ghcr.io/reidmaks/apn:staging<br/>(New Digest)"]
    end

    subgraph Cluster["Hybrid Talos Kubernetes Cluster"]
        subgraph KubeSystem["Namespace: kube-system"]
            Keel["Keel Operator (keel:1.2.2)<br/>Polling @every 1m"]
        end

        subgraph APN_NS["Namespace: apn"]
            Secret["Secret: ghcr-secret<br/>(Docker registry credentials)"]
            Deployment["Deployment: apn-wordpress<br/>(bjw-s app-template)"]
            Pod["Pod: apn-wordpress-xxx"]
        end

        subgraph Notifications["Observability"]
            Ntfy["ntfy.sh (<redacted-topic>)"]
        end
    end

    GHA -->|1. Push new image| GHCR
    Keel -->|2. Poll registry digest using ghcr-secret| GHCR
    Keel -->|3. Trigger rolling restart on digest change| Deployment
    Deployment -->|4. Pull fresh image & recreate pod| Pod
    Keel -->|5. Send notification via Webhook| Ntfy
```

## Architectural Decisions (Historical)

### 1. Choice of Controller: Keel vs. ArgoCD vs. Push Webhook
- **ArgoCD + Image Updater:** Rejected for this use case due to resource constraints (~500MB–1.2GB RAM across 5+ pods) and conflict with our "Terraform for everything" workload management model.
- **Push Webhook:** Highly efficient, but requires exposing a dedicated webhook receiver endpoint to the public Internet and maintaining deploy secrets across external GitHub repositories.
- **Keel:** Originally selected because it was lightweight (~30–50MB RAM), ran inside the cluster, and handled digest-based updates on mutable tags. Later decommissioned in [[034-renovate-gitops-updates]] in favor of Renovate Bot.

### 2. Registry Authentication
Keel utilized the workload's existing registry credentials:
- Deployment annotation `keel.sh/imagePullSecret: "ghcr-secret"` instructed Keel to read the credentials from `apn/ghcr-secret`.
- Keel's ClusterRole was granted `get`, `list`, `watch` on secrets cluster-wide to fetch authentication tokens dynamically for polling private and rate-limited registries.

### 3. Workload Policy Configuration
For mutable staging tags (`staging`), the following annotations were configured on `apn-wordpress`:
```yaml
annotations:
  keel.sh/policy: "force"            # Check SHA manifest digest changes on mutable tags
  keel.sh/trigger: "poll"            # Actively poll the remote registry
  keel.sh/matchTag: "true"           # Only redeploy if the incoming tag matches the configured tag
  keel.sh/match-tag: "true"          # Compatibility alias for legacy Keel versions
  keel.sh/pollSchedule: "@every 1m"  # Check GHCR every 1 minute
  keel.sh/imagePullSecret: "ghcr-secret"
```

### 4. Notifications
Keel utilized its native **Webhook** notification sender (`WEBHOOK_ENDPOINT: "https://ntfy.sh/<redacted-topic>"`) to dispatch deployment notifications directly to the cluster `ntfy` topic.

## References
- [[025-apn-public-ingress-and-dns]]
- [[034-renovate-gitops-updates]]
- [[INDEX]]
