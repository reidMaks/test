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

# Show logs for a workload in default or ci namespace
[group('diagnostics')]
logs deploy namespace="default":
    kubectl logs -n "{{namespace}}" "deploy/{{deploy}}" --tail=100 -f

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

# Delete orphaned PersistentVolumes in 'Released' state and their detached Longhorn volumes
[group('maintenance')]
[confirm("Delete all orphaned 'Released' PersistentVolumes and their detached Longhorn volumes? (y/N)")]
clean-released-pvs:
    #!/usr/bin/env bash
    set -euo pipefail
    RELEASED_PVS=$(kubectl get pv --no-headers | awk '$5 == "Released" {print $1}')
    if [ -z "$RELEASED_PVS" ]; then
        echo "No Released PVs found."
        exit 0
    fi
    echo "Deleting Released PVs: $RELEASED_PVS"
    echo "$RELEASED_PVS" | xargs -r kubectl delete pv
    echo "$RELEASED_PVS" | xargs -r kubectl delete volumes.longhorn.io -n longhorn-system --ignore-not-found
