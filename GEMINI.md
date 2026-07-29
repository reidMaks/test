# Antigravity (AGY) Project Rules: IaaC

## 1. Core Safety & Execution (CRITICAL)
- **NO AUTOMATIC APPLY:** You are strictly forbidden from automatically running deployment commands (e.g., `terraform apply`, `kubectl apply`) or any commands that mutate infrastructure state.
- **Explanation First:** You must always explain what you plan to do, write the necessary code, and explain *why* it's needed.
- **Read-Only Allowed:** You may run read-only commands (e.g., `terraform plan`, `ls`, reading files) to understand the environment, but you must report findings back to the user.
- **User Approval & Deployment:** The user will manually run the deployment commands. If anything needs to be created or deleted outside of standard IaaC files, you must get explicit permission.

## 2. Language & Interaction
- **User Language:** The user communicates in Ukrainian. You MUST reply in Ukrainian.
- **Documentation Language:** ALL project documentation, agent instructions, ADRs, and architecture files MUST be written and maintained in **English**.

## 3. Architecture Knowledge Base (Obsidian Wiki)
- **Micro-Docs + Index:** We maintain an Obsidian-style linked Markdown wiki in `docs/architecture/`. We use small Architecture Decision Records (ADRs) and specific component files, linked together via a central `INDEX.md`.
- **MANDATORY RULE:** When infrastructure changes, you must create or update the relevant micro-docs (e.g., `001-add-redis.md`) and ensure `INDEX.md` links to them using Obsidian-style links (e.g., `[[001-add-redis]]`).
- **Diagrams:** Use Mermaid.js for network and topology diagrams.

## 4. Project Architecture (IaaC)
- **Approach:** "Terraform for everything" (VM provisioning, cluster init, workloads).
- **Cluster (Talos Linux):** Hybrid Kubernetes cluster. Control plane/workers on local Proxmox (`192.168.0.0/24`), extra nodes on Oracle Cloud (OCI). Managed in the `infra/` directory.
- **Workloads:** Kubernetes resources in `workload/`. Key services: Traefik (Ingress), MetalLB (LoadBalancer), Longhorn (Storage).
- **Secrets Management (CRITICAL):** NO hardcoded secrets in Git. Fetch dynamically from Bitwarden using the `bitwarden-secrets` Terraform provider.

## 5. RTK (Rust Token Killer)
- The user utilizes a CLI proxy called `rtk`. Format your command executions and suggestions through `rtk` where applicable.
