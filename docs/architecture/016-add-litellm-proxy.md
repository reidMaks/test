# 016 - Add LiteLLM Proxy

**Date:** 2026-08-06
**Status:** Accepted

## Context
The user requested a solution for automated routing of LLM requests to OpenRouter based on cost constraints and for centralizing model selection for different sub-agents in Open WebUI. Instead of connecting Open WebUI directly to OpenRouter, we need a proxy that can manage routing, set budgets, and expose standard agent endpoints (e.g., `agent-smart`, `agent-fast`) that internally route to the most cost-effective models.

## Decision
- Deploy **LiteLLM** as an intermediate proxy between Open WebUI and OpenRouter.
- We provision a CloudNativePG database for LiteLLM in the `shared-db` cluster, ensuring it has persistent state for its Admin UI, budgets, and dynamic model configuration.
- We do **not** hardcode models in the Terraform configuration. Instead, LiteLLM is initialized with the database and an Admin UI, allowing the user to configure models, keys, and routing dynamically via the Web UI (`litellm.kms-lab.in.ua`).
- Open WebUI connects to LiteLLM's internal cluster service (`http://litellm.default.svc.cluster.local:4000/v1`) using the generated `LITELLM_MASTER_KEY` (configured manually via Open WebUI Admin Settings Connections panel).

## Consequences
- Open WebUI no longer needs to be updated or restarted when new OpenRouter models are added; they can simply be mapped in LiteLLM's UI.
- LiteLLM provides detailed cost tracking and spend limits.
- Model names can be abstracted (e.g., exposing just `budget-agent` to Open WebUI), decoupling the end-user interface from the underlying model provider's naming schemes.
