# ADR 015: Open WebUI RAG Architecture (PGVector & OIKB)

## Date
2026-08-04

## Context
Open WebUI serves as our primary LLM chat interface. To make it a capable infrastructure assistant, it requires deep contextual awareness of the IaaC repository (Kubernetes manifests, Terraform states, and ADR documentation).
By default, Open WebUI uses a local SQLite database for chat history and a local ChromaDB instance for vector storage (Knowledge Base / RAG). This required persistent volumes (`PVs`) and prevented stateless, highly-available deployments. Furthermore, manually uploading project files to the Knowledge Base quickly leads to outdated context as the repository evolves.

## Decision

1. **Stateless Open WebUI via CloudNativePG (`pgvector`)**
   - We migrated both the main application database and the vector database to our existing CloudNativePG `shared-db` cluster.
   - We declaratively enabled the `vector` extension on the `openwebui` database using the CNPG `Database` manifest.
   - We configured the `open-webui` Helm release with `DATABASE_URL` pointing to PostgreSQL and `VECTOR_DB=pgvector` via `extraEnvVars`, allowing us to disable `persistence` entirely.

2. **Automated Knowledge Base Sync (`oikb`)**
   - We deployed the official `oikb` (Open WebUI Knowledge Base Sync) daemon.
   - `oikb` is configured to periodically poll the private GitHub repository (`reidMaks/test`) and automatically push codebase updates directly into the Open WebUI Knowledge Base API.
   - This ensures the AI agent always has up-to-date semantic context (RAG) of the infrastructure without manual intervention.

3. **Active Repository Management (GitHub MCP)**
   - To complement RAG, we added `mcp-server-github` to the `mcpo` proxy, securely injecting a GitHub Personal Access Token.
   - This empowers the AI agent to not only read the documentation instantly via RAG but also write new ADRs, modify code, and create Pull Requests on demand.

## Consequences
- **Positive:** Open WebUI is now fully stateless and scalable. The AI agent acts as a true DevOps team member with instant context and read/write capabilities to the IaaC repository.
- **Negative:** Increased dependency on the `shared-db` availability. Open WebUI will fail to start if CNPG is down. `oikb` introduces a background process requiring internal API access.
