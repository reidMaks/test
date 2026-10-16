# 024 Deploy "It's a Plan" AI-Native Issue Tracker

**Status:** Implemented (Updated to v1.5.0)
**Date:** 2026-09-29 (Updated 2026-10-16)

## Context

We require a central, self-hosted issue tracker and project management platform to coordinate work between human engineers and autonomous AI coding agents (such as Antigravity, Claude Code, and Cursor).

Previous alternatives like Plane or Jira have high memory footprints (2.5 GB to 4+ GB of RAM) and lack native agent-first primitives. **It's a Plan** (`croffasia/itsaplan`) is a modern, lightweight platform built on Bun, Elysia, Drizzle ORM, and Next.js that runs in ~400–600 MB of RAM across all pods.

Crucially, It's a Plan treats AI agents as first-class team members with dedicated `@username` accounts, permission sets, autonomous task lifecycles, and a native Model Context Protocol (MCP) server endpoint (`/mcp`).

## Architecture & Topology

```mermaid
flowchart TD
    subgraph Clients["Clients & Agents"]
        Browser["User Browser (Web UI)"]
        AIAgents["AI Agents (Claude Code, Antigravity, Cursor)"]
    end

    subgraph IngressLayer["Ingress & Routing (Traefik)"]
        Traefik["Traefik Ingress Controller<br/>Wildcard TLS (*.kms-lab.in.ua)"]
    end

    subgraph ManagementNS["Namespace: management"]
        WebPod["itsaplan-web:3001<br/>(Next.js SSR Frontend)"]
        APIPod["itsaplan-api:3000<br/>init: migrate<br/>app: Bun + Elysia REST & MCP"]
        WorkerPod["itsaplan-worker<br/>init: wait-for-migrations<br/>app: Task Scheduler & Webhooks"]
        InitJob["itsaplan-minio-bucket-init<br/>(S3 Init Job via rustfs/rustfs:1.0.0)"]
    end

    subgraph StorageLayer["Cluster Data & State"]
        CNPG["CloudNativePG (shared-db)<br/>shared-db-rw.cnpg-system.svc:5432"]
        MinIO["Local MinIO (S3 Object Store)<br/>minio.default.svc:9000"]
    end

    Browser -->|https://plan.kms-lab.in.ua| Traefik
    AIAgents -->|https://plan-api.kms-lab.in.ua/mcp| Traefik

    Traefik -->|plan.kms-lab.in.ua| WebPod
    Traefik -->|plan-api.kms-lab.in.ua| APIPod

    WebPod -.->|Browser calls API directly| APIPod
    APIPod -->|DB: itsaplan| CNPG
    WorkerPod -->|DB: itsaplan| CNPG
    APIPod -->|S3: itsaplan-attachments| MinIO
    WorkerPod -->|S3: itsaplan-attachments| MinIO
    InitJob -->|PUT bucket (--aws-sigv4)| MinIO
```

## Architectural Decisions & Environment Adaptations

1. **Dual Ingress Hostnames (`plan` and `plan-api`):**
   - The Elysia backend relies on `better-auth` mounted at `/api/auth/*`. Better-auth does not support running behind a subpath prefix (e.g. `/api`) on the same domain as the frontend without breaking path resolution.
   - We separate the services into two distinct single-level subdomains:
     - `plan.kms-lab.in.ua` for Next.js Web UI (`itsaplan-web`, port 3001).
     - `plan-api.kms-lab.in.ua` for Elysia API & MCP server (`itsaplan-api`, port 3000).
   - Single-level subdomains are natively protected by our cluster-wide Let's Encrypt wildcard certificate (`*.kms-lab.in.ua`) and Cloudflare Universal SSL (which does not support multi-level subdomains like `api.plan.kms-lab.in.ua` on the free tier).
   - `COOKIE_DOMAIN` is set to `.kms-lab.in.ua` to allow seamless session sharing between `plan` and `plan-api`.

2. **CloudNativePG (`shared-db`) & Decoupled Migration Lifecycle:**
   - Dedicated database `itsaplan` and user `itsaplan` are provisioned declaratively in `cnpg-system` using `DatabaseRole` and `Database` custom resources.
   - Connection URL: `postgresql://itsaplan:<PASSWORD>@shared-db-rw.cnpg-system.svc.cluster.local:5432/itsaplan`.
   - In `v1.2.0+`, migrations are completely decoupled from runtime containers:
     - `itsaplan-api` runs an `initContainers` named `migrate` (`bun run packages/db/src/migrate.ts`) coordinating via PostgreSQL advisory lock `804216551`.
     - `itsaplan-worker` runs an `initContainers` named `wait-for-migrations` (`bun run packages/db/src/wait-for-migrations.ts`) polling `drizzle.__drizzle_migrations` until schema updates complete.
   - Starting in `v1.4.0`, the upstream `api` image bundles the PostgreSQL 18 `pg_dump` client (`#492`). `SKIP_PRE_MIGRATION_BACKUP` remains set to `"1"` because we keep `api.backups.persistence.enabled: false` (avoiding an extra PVC on OCI) and delegate database backups to CNPG at the cluster level.

3. **Object Storage & Replacement of `quay.io/minio/mc` with `rustfs/rustfs`:**
   - Attachments are stored in the cluster's local S3 object store (`http://minio.default.svc.cluster.local:9000`) in bucket `itsaplan-attachments` (`minio.enabled: false`, `externalS3.endpoint` configured, `S3_FORCE_PATH_STYLE: "true"`).
   - Upstream `v1.2.0` (`#437`) replaced `quay.io/minio/minio` and `quay.io/minio/mc` with `rustfs/rustfs:1.0.0` after MinIO discontinued free public container images on Quay.io (`401 UNAUTHORIZED`).
   - Following upstream `job-minio-init.yaml`, our declarative `kubernetes_job_v1.itsaplan_minio_bucket_init` now uses `rustfs/rustfs:1.0.0` and initializes the bucket via `curl -X PUT --aws-sigv4 aws:amz:us-east-1:s3` (accepting both HTTP `200` and `409 BucketAlreadyOwnedByYou` for idempotency across MinIO and RustFS).

4. **Multi-Arch Container Images from GHCR (`v1.5.0`):**
   - Official images are pulled from GitHub Container Registry (`ghcr.io/croffasia/itsaplan-*`), pinned to release tag `1.5.0` (bringing Workspaces & Project Archiving from `v1.3.0`, status-triggered agent schedules & PG18 client from `v1.4.0`, and encrypted OAuth tokens at rest, account deactivation, workspace model pricing, and PWA support from `v1.5.0`).
   - Images provide native multi-architecture support (`linux/amd64` for Proxmox workers and `linux/arm64` for OCI nodes).

5. **Resource Efficiency & Omission of `itsaplan-bot`:**
   - In `croffasia/itsaplan`, agent schedulers and background tasks are embedded in `itsaplan-worker` (using `croner`).
   - The `itsaplan-bot` container is exclusively a Telegram bot integration (`grammy`). We disable `bot` (`bot.enabled: false`) to eliminate redundant resource consumption.

## Consequences

- **Low Resource Usage:** Entire tracker runs under ~500 MB RAM across all 3 containers.
- **Agent Integration:** AI agents can connect directly via HTTP/SSE MCP at `https://plan-api.kms-lab.in.ua/mcp` using API keys (`x-api-key`).
- **Autonomous & Safe:** Fully decoupled from external cloud billing; data stays within local Ceph/Longhorn and local CNPG.
