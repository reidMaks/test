# Task: Deploy "It's a Plan" (AI-Native Issue Tracker) in Hybrid Kubernetes Cluster

> **Target Environment:** Hybrid Talos Linux Kubernetes Cluster (`/home/max/pet/IaaC`)
> **Status:** Ready for Execution by IaaC Agent
> **Target Ingress Domain:** `plan.kms-lab.in.ua`
> **Namespace:** `management`

---

## 1. Executive Summary & Objective

Deploy **It's a Plan** ([github.com/croffasia/itsaplan](https://github.com/croffasia/itsaplan), [itsaplan.dev](https://itsaplan.dev)) as the central, self-hosted project management and issue-tracking platform for hybrid engineering teams (humans + autonomous AI agents).

This service will serve as the central coordination hub for:
1. **APN** (Educational platform with specialized subagents: `@lms_engineer`, `@devops_sre`, `@legal_compliance`, `@content_curriculum`, `@funnel_automator`).
2. **Future projects** in the cluster via multi-workspace support.

---

## 2. Why "It's a Plan" (Architecture Rationale)

- **AI Agents as First-Class Citizens:** Agents are registered as project members with dedicated `@username`, roles, permissions, and tool assignments.
- **Native Model Context Protocol (MCP) Server:** Native MCP support out-of-the-box (`/mcp` endpoint), allowing Antigravity, Claude Code, and Cursor to query, claim, update, and close issues with near-zero token overhead compared to legacy Jira REST APIs.
- **Lightweight Modern Stack:** Built on Bun, Elysia, Drizzle ORM, and Next.js (~300–500 MB RAM across all containers, vs. 2.5 GB for Plane).
- **Autonomous Lifecycle ("Auto-Done"):** Agents autonomously claim delegated tasks, verify acceptance criteria, attach execution proofs (logs, diffs, headless screenshots) to comments, and mark issues as `Done`.
- **Scheduled Agent Workflows:** Built-in cron runner for recurring agent maintenance tasks (e.g. daily triage, webhook health checks).

---

## 3. Infrastructure & Deployment Specification

### 3.1. Namespace & Network Placement
- **Namespace:** `management` (create if absent with `pod-security.kubernetes.io/enforce: baseline`).
- **Ingress Controller:** Traefik.
- **Ingress Hosts:**
  - Web UI: `plan.kms-lab.in.ua`
  - API & MCP Server: `plan-api.kms-lab.in.ua`
- **TLS:** Terminated at Traefik Ingress using cluster wildcard certificate (`*.kms-lab.in.ua`).

### 3.2. Database Configuration (CloudNativePG)
- **Database Engine:** High-Availability PostgreSQL via existing `CloudNativePG` cluster (`shared-db` in namespace `cnpg-system`).
- **Provisioning:**
  - Declaratively create `DatabaseRole` and `Database` `itsaplan` via Terraform in `cnpg-system`.
  - Passwords generated via Terraform `random_password`.
  - Connection string format:
    ```
    postgresql://itsaplan:<PASSWORD>@shared-db-rw.cnpg-system.svc.cluster.local:5432/itsaplan
    ```

### 3.3. Object Storage (S3 / Attachments)
- **Storage Target:** Cluster local MinIO instance (`http://minio.default.svc.cluster.local:9000`).
- **Bucket:** `itsaplan-attachments` (automatically initialized via one-off `mc` Job).
- **Path Style:** `S3_FORCE_PATH_STYLE: "true"`.

### 3.4. Required Container Images & Services
Deploy via official vendored Helm chart (`workload/charts/itsaplan`):
1. **`itsaplan-api`** (`ghcr.io/croffasia/itsaplan-api:1.0.0`):
   - Elysia / Bun backend.
   - Automatically runs database migrations on startup.
   - Exposes REST API and `/mcp` server endpoint on port `3000`.
2. **`itsaplan-web`** (`ghcr.io/croffasia/itsaplan-web:1.0.0`):
   - Next.js frontend UI.
   - Exposes Web UI on port `3001`.
3. **`itsaplan-worker`** (`ghcr.io/croffasia/itsaplan-worker:1.0.0`):
   - Background job runner, notifications, agent recurring scheduler (`croner`), webhooks.
4. **`itsaplan-bot`** (`ghcr.io/croffasia/itsaplan-bot:1.0.0`):
   - Dedicated Telegram bot integration (optional, disabled by default).

### 3.5. Required Environment Variables & Secrets
Configured directly via Helm chart values:

| Variable | Source / Description |
| :--- | :--- |
| `API_URL` | `https://plan-api.kms-lab.in.ua` |
| `APP_URL` | `https://plan.kms-lab.in.ua` |
| `COOKIE_DOMAIN` | `.kms-lab.in.ua` (for shared cross-subdomain auth cookies) |
| `DATABASE_URL` | CNPG connection string: `postgresql://itsaplan:...@shared-db-rw.cnpg-system.svc.cluster.local:5432/itsaplan` |
| `BETTER_AUTH_SECRET` | 32-character random string (`random_password`) |
| `APP_ENCRYPTION_KEY` | 32-character random string (`random_password`) |
| `S3_ENDPOINT` | `http://minio.default.svc.cluster.local:9000` |
| `S3_BUCKET` | `itsaplan-attachments` |
| `S3_ACCESS_KEY_ID` | `admin` |
| `S3_SECRET_ACCESS_KEY` | MinIO root password from Bitwarden |
| `S3_FORCE_PATH_STYLE` | `"true"` |
| `TELEMETRY_DISABLED` | `"1"` |
| `DO_NOT_TRACK` | `"1"` |

---

## 4. Initial Workspace & Agent Provisioning

Once deployed and initialized:
1. **Initial Admin Setup:**
   - Access `https://plan.kms-lab.in.ua` and register the instance administrator account (`max`).
2. **Workspace Creation:**
   - Create workspace: **`APN`** (slug: `apn`).
3. **Seed AI Agent Accounts in `APN` Workspace:**
   Register the following agent accounts with appropriate roles:
   - `@techlead` — Orchestrator and task designer.
   - `@lms_engineer` — WordPress, WooCommerce, TutorLMS, and WP-CLI automation.
   - `@devops_sre` — K8s infrastructure, logging, networking, headless visual validation.
   - `@legal_compliance` — E-commerce legal docs (offer, privacy, GDPR/tax compliance).
   - `@content_curriculum` — Course copy, curriculum, and educational materials.
   - `@funnel_automator` — ManyChat, Instagram Direct, and Telegram automations.
4. **Generate Agent API / MCP Tokens:**
   - Generate personal access tokens for each agent to enable direct MCP and REST interaction.

---

## 5. Model Context Protocol (MCP) Integration

Configure the remote MCP server in Antigravity / Claude Code / Cursor:

```json
{
  "mcpServers": {
    "itsaplan": {
      "url": "https://plan-api.kms-lab.in.ua/mcp",
      "headers": {
        "x-api-key": "<AGENT_PERSONAL_API_KEY>"
      }
    }
  }
}
```

---

## 6. Acceptance & Verification Steps for IaaC Agent

1. [ ] **PostgreSQL Readiness:** Database `itsaplan` created and accessible via CNPG cluster in `cnpg-system`.
2. [ ] **MinIO Bucket:** Bucket `itsaplan-attachments` created and accessible.
3. [ ] **Pod Status:** All pods (`api`, `web`, `worker`) are in `Running` state and passing liveness/readiness probes.
4. [ ] **Ingress Verification:** Headless / curl check verifying `https://plan.kms-lab.in.ua` returns `200 OK` with the login screen.
5. [ ] **MCP Endpoint:** `https://plan-api.kms-lab.in.ua/mcp` responds to MCP protocol requests.
6. [ ] **Documentation:** Record architectural decision in `/home/max/pet/IaaC/docs/architecture/024-itsaplan-ai-issue-tracker.md`.
