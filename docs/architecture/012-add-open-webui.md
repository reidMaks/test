# 012 - Add Open WebUI

**Date:** 2026-08-03
**Status:** Accepted

## Context
We need a modern, feature-rich chat interface for interaction with Large Language Models (LLMs). The user requested to deploy Open WebUI into the cluster.

## Decision
- We use the official `open-webui` Helm chart.
- We disable the bundled Ollama instance (`ollama.enabled=false`) to conserve cluster resources since we rely on external LLM APIs (OpenRouter).
- The OpenRouter API key is reused from the existing Bitwarden secret (`open_router_api_key`) and passed as `OPENAI_API_KEY`. The API base URL is set to `https://openrouter.ai/api/v1`.
- Traefik ingress is configured for the domain `openui.kms-lab.in.ua`.
- Persistence is completely disabled (`persistence.enabled: false`) to keep the deployment stateless, avoiding the need for volume replication. Document uploads and RAG embeddings will be stored ephemerally.
- Database is migrated from default SQLite to PostgreSQL via CloudNativePG (CNPG) in the `shared-db` cluster, ensuring high availability and proper backups.
- The bundled Redis (used for WebSockets) is disabled, and Open WebUI is configured to use the `shared-redis` cluster (using DB index `4`).

## Consequences
- The cluster gets a lightweight web UI without running heavy local LLM models.
- The UI allows multi-model conversational experiences using OpenRouter's capabilities.
- Proper secret management is maintained using Bitwarden.
- Storing state in CloudNativePG provides centralized, backed-up database management, while keeping local PVC usage minimal.
