# ==============================================================================
# IaaC Command Runner (justfile) — Single Entrypoint for Terraform & K8s Ops
# Usage: run `just` to list all commands, e.g. `just apply`, `just plan infra`
# ==============================================================================

set shell := ["bash", "-euo", "pipefail", "-c"]

export KUBECONFIG := justfile_directory() + "/infra/kubeconfig"
export TALOSCONFIG := justfile_directory() + "/infra/talosconfig"

# List all available recipes
default:
    @just --list --unsorted

# ==============================================================================
# 1. Terraform Operations (Modules: workload | infra | qnap)
# ==============================================================================

# Initialize Terraform in a specific module (default: workload)
[group('terraform')]
init module="workload":
    cd "{{module}}" && terraform init

# Format Terraform files across all modules
[group('terraform')]
fmt:
    terraform fmt -recursive infra/ workload/ qnap/

# Validate Terraform configuration across infra, workload, and qnap
[group('terraform')]
validate:
    @echo "=== Validating infra/ ==="
    cd infra && terraform validate
    @echo "=== Validating workload/ ==="
    cd workload && terraform validate
    @echo "=== Validating qnap/ ==="
    cd qnap && terraform validate

# Run read-only Terraform plan in a module (workload | infra | qnap)
[group('terraform')]
plan module="workload":
    cd "{{module}}" && terraform plan

# Apply Terraform changes in a module (workload | infra | qnap)
[group('terraform')]
[confirm("Apply Terraform changes in '{{module}}'? (y/N)")]
apply module="workload":
    cd "{{module}}" && terraform apply

# ==============================================================================
# 2. Cluster Diagnostics (Read-Only)
# ==============================================================================

# Show cluster summary: nodes, resource usage, CNPG status, and non-Running pods
[group('diagnostics')]
status:
    @echo "=== Kubernetes Nodes ==="
    kubectl get nodes -o wide
    @echo "\n=== Node Resource Usage (CPU / Memory) ==="
    kubectl top nodes || true
    @echo "\n=== CloudNativePG (shared-db) Status ==="
    kubectl get cluster,pods -n cnpg-system -o wide
    @echo "\n=== Non-Running / Problematic Pods ==="
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Inspect Longhorn disk capacity, volume health, and any orphaned Released PVs
[group('diagnostics')]
storage:
    @echo "=== Longhorn Node Disk Capacity ==="
    kubectl get nodes.longhorn.io -n longhorn-system -o custom-columns="NODE:.metadata.name,ZONE:.status.zone,SCHEDULABLE:.spec.allowScheduling,MAX_BYTES:.status.diskStatus.*.storageMaximum,SCHEDULED_BYTES:.status.diskStatus.*.storageScheduled,AVAILABLE_BYTES:.status.diskStatus.*.storageAvailable"
    @echo "\n=== Longhorn Volumes ==="
    kubectl get volumes.longhorn.io -n longhorn-system -o custom-columns="NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,NODE:.status.currentNodeID,PVC:.status.kubernetesStatus.pvcName,PV_STATUS:.status.kubernetesStatus.pvStatus,SIZE:.spec.size"
    @echo "\n=== Orphaned (Released) PersistentVolumes ==="
    kubectl get pv | awk 'NR==1 || /Released/'
    @echo "\n=== Orphaned Longhorn Replicas ==="
    kubectl get orphans.longhorn.io -n longhorn-system || true

# Show logs for a workload in default or ci namespace
[group('diagnostics')]
logs deploy namespace="default":
    kubectl logs -n "{{namespace}}" "deploy/{{deploy}}" --tail=100 -f

# Show RustDesk self-hosted server public key, ready-to-import client config string, and mobile QR code
[group('diagnostics')]
rustdesk-config:
    #!/usr/bin/env bash
    set -euo pipefail
    HOST="152.67.85.188"
    API="https://rustdesk-api.kms-lab.in.ua"
    PUBKEY=$(kubectl exec -n default deploy/rustdesk -c litestream -- cat /root/id_ed25519.pub | tr -d '[:space:]')
    JSON_CFG=$(printf '{"host":"%s","key":"%s","api":"%s"}' "$HOST" "$PUBKEY" "$API")
    CONFIG_STR=$(printf '%s' "$JSON_CFG" | base64 -w0 | sed 's/=*$//' | rev)
    echo "=== RustDesk Server Configuration ==="
    echo "ID Server : $HOST (or rustdesk.kms-lab.in.ua)"
    echo "Relay     : $HOST"
    echo "API Server: $API"
    echo "Public Key: $PUBKEY"
    echo ""
    echo "=== Ready-to-Import Config String (Clipboard / --config) ==="
    echo "$CONFIG_STR"
    echo ""
    echo "=== Mobile QR Code (Settings -> ID/Relay Server -> Scan QR) ==="
    /usr/bin/python3 -c "import qrcode; qr = qrcode.QRCode(border=1); qr.add_data('config=$JSON_CFG'); qr.make(fit=True); qr.print_ascii(invert=True)"

# ==============================================================================
# 3. Maintenance & Hygiene
# ==============================================================================

# Delete Completed (Succeeded) and Failed/Evicted pods across all namespaces
[group('maintenance')]
[confirm("Delete all Completed/Failed pods across all namespaces? (y/N)")]
clean-pods:
    kubectl delete pods -A --field-selector=status.phase==Succeeded
    kubectl delete pods -A --field-selector=status.phase==Failed
    @echo "Cleaned up terminated pods."

# Delete orphaned PersistentVolumes in 'Released' state, detached Longhorn volumes, and Longhorn Orphan replicas
[group('maintenance')]
[confirm("Delete all orphaned 'Released' PersistentVolumes and Longhorn Orphan replicas? (y/N)")]
clean-released-pvs:
    #!/usr/bin/env bash
    set -euo pipefail
    RELEASED_PVS=$(kubectl get pv --no-headers | awk '$5 == "Released" {print $1}')
    if [ -n "$RELEASED_PVS" ]; then
        echo "Deleting Released PVs: $RELEASED_PVS"
        echo "$RELEASED_PVS" | xargs -r kubectl delete pv
        echo "$RELEASED_PVS" | xargs -r kubectl delete volumes.longhorn.io -n longhorn-system --ignore-not-found
    else
        echo "No Released PVs found."
    fi
    echo "Cleaning up Longhorn Orphan replicas..."
    kubectl delete orphans.longhorn.io -n longhorn-system --all

# Build the shared It's a Plan Agent Runner base image natively on TV-Box (192.168.0.106)
[group('maintenance')]
[confirm("Build and tag 'itsaplan-runner-base' on TV-Box (192.168.0.106)? (y/N)")]
build-runner-base host="max@192.168.0.106":
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(sed -n 's/^ARG RUNNER_VERSION=\(.*\)/\1/p' qnap/itsaplan-runner-base/Dockerfile)
    echo "Syncing qnap/itsaplan-runner-base (RUNNER_VERSION=$VERSION) to {{host}}..."
    ssh "{{host}}" "mkdir -p /home/max/itsaplan-runner-base/git-hooks"
    scp -q qnap/itsaplan-runner-base/Dockerfile qnap/itsaplan-runner-base/entrypoint.sh qnap/itsaplan-runner-base/README.md "{{host}}:/home/max/itsaplan-runner-base/"
    scp -q qnap/itsaplan-runner-base/git-hooks/* "{{host}}:/home/max/itsaplan-runner-base/git-hooks/"
    ssh "{{host}}" "cd /home/max/itsaplan-runner-base && chmod +x entrypoint.sh git-hooks/* && docker build --pull -t itsaplan-runner-base:${VERSION} -t itsaplan-runner-base:latest -t git.kms-lab.in.ua/max/itsaplan-runner-base:${VERSION} -t git.kms-lab.in.ua/max/itsaplan-runner-base:latest ."
    echo "✅ Base image itsaplan-runner-base:${VERSION} built and tagged on {{host}}"
