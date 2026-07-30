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

### 3. Frontend Localization via Custom Image
Since Next.js UI translations are embedded into the compiled frontend build, we manually generated `messages/uk.json` (translated from `en.json`), added `"uk"` to the `SUPPORTED_LOCALES`, and rebuilt the Docker image locally.
- **Image:** `ttl.sh/freelingo-frontend-uk-max-001:1h`
- **Node Affinity:** Because the local machine architecture (`amd64`) differs from the OCI nodes (`arm64`), we applied a `nodeSelector` (`kubernetes.io/arch: amd64`) in `values.yaml` to ensure the frontend pod runs on compatible nodes (e.g. Proxmox local workers).

### 4. Secrets Management Refactoring
To comply with the rule of "no hardcoded secrets in Git," we consolidated the PostgreSQL password, Redis password, and Secret Key into a single JSON object stored in Bitwarden (`freelingo_env`).
- Terraform dynamically fetches this JSON using the `bitwarden-secrets` provider and parses it using `jsondecode()`.
- The OpenRouter API key remains as a separate standalone Bitwarden secret (`open_router_api_key`) and is merged into the final `kubernetes_secret.freelingo` mapping.

## Consequences
- The cluster's secret hygiene is maintained.
- FreeLingo supports Ukrainian natively in both the backend and frontend.
- Future frontend changes or FreeLingo updates will require either pushing a PR upstream to the official FreeLingo repo or maintaining a custom Docker image build process for the frontend.
