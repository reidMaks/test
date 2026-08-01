# 007 FreeLingo Localization and Secrets Management

## Status
Accepted

## Context
We deployed the FreeLingo application into the cluster. During configuration, we encountered several challenges:
1. **Language Support:** The FreeLingo backend hardcodes supported languages. We needed to add Ukrainian (`"uk"`) to the Native Languages list.
2. **LLM Integration:** Various Llama models from OpenRouter returned 404 errors due to endpoint changes or missing permissions. We needed a model that works reliably and has good Ukrainian language support.
3. **Frontend Localization:** The frontend did not include a Ukrainian localization (`uk.json`). Next.js compiled output makes it difficult to patch UI translations dynamically via ConfigMaps.
4. **Secrets Management:** The initial Terraform configuration stored `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, and `SECRET_KEY` as hardcoded plaintext in `freelingo.tf`, violating the `GEMINI.md` project rules for Bitwarden-only secrets.

## Decisions

### 1. Backend Language Patching
We utilize Kubernetes ConfigMaps to patch `auth.py` and `admin.py` in the FreeLingo backend container. This adds `"uk"` to the allowed native languages schema without rebuilding the backend image.

### 2. Model Selection
We updated the OpenRouter model configuration in `values.yaml` to use `qwen/qwen3.7-flash`. This model provides robust multi-language support (including Ukrainian), is cost-effective, and currently functions correctly without endpoint 404 errors.

### 3. Frontend Localization via GitHub Actions
Since Next.js UI translations are embedded into the compiled frontend build, we manually generated `messages/uk.json` (translated from `en.json`) and added `"uk"` to the `SUPPORTED_LOCALES`.
To ensure High Availability (HA) across our `amd64` (home) and `arm64` (OCI) nodes, we automated the multi-architecture build process using GitHub Actions:
- **Workflow:** `.github/workflows/build-freelingo.yml` automatically clones the official repo, injects `uk.json`, modifies locales, and builds/pushes the image using Docker Buildx.
- **Image:** `ghcr.io/reidmaks/freelingo-frontend:latest` (Public Package on GHCR).
- **Node Affinity:** Removed previous `amd64` nodeSelectors. The frontend (along with Kokoro and Whisper) now runs natively on both architectures.

### 4. Secrets Management Refactoring
To comply with the rule of "no hardcoded secrets in Git," we consolidated the PostgreSQL password, Redis password, and Secret Key into a single JSON object stored in Bitwarden (`freelingo_env`).
- Terraform dynamically fetches this JSON using the `bitwarden-secrets` provider and parses it using `jsondecode()`.
- The OpenRouter API key remains as a separate standalone Bitwarden secret (`open_router_api_key`) and is merged into the final `kubernetes_secret.freelingo` mapping.

## Consequences
- The cluster's secret hygiene is maintained.
- FreeLingo supports Ukrainian natively in both the backend and frontend.
- Future frontend changes or FreeLingo updates will require either pushing a PR upstream to the official FreeLingo repo or maintaining a custom Docker image build process for the frontend.
