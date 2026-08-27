# 018 - Add Headroom Proxy

**Date:** 2026-08-13
**Status:** Accepted

## Context
Coding-agent traffic (Claude Code) and LiteLLM's upstream calls send large tool outputs, logs, and RAG chunks to the model provider uncompressed, wasting tokens. [Headroom](https://github.com/headroomlabs-ai/headroom) is a context-compression proxy that sits between a client and the provider API, rewriting verbose payloads into compact representations before they're sent, with 60-95% token reduction on JSON/tool-output-heavy payloads.

Three traffic sources were considered for routing through Headroom:
- **Claude Code** (this CLI) — supports a custom `ANTHROPIC_BASE_URL`.
- **LiteLLM** — proxies Open WebUI's calls to OpenRouter (see [[016-add-litellm-proxy]]).
- **agy** (Antigravity CLI) — investigated and **excluded**. It talks to Google's own multi-model backend over gRPC (Vertex-AI-style method paths), exposes no base-url/proxy flag, and gRPC clients don't reliably honor `HTTPS_PROXY`. Rerouting it would require an unsupported MITM hack, so it stays direct.

## Decision
- Deploy the official Headroom proxy image (`ghcr.io/headroomlabs-ai/headroom:latest`) as a standalone Deployment/Service/Ingress (`workload/headroom.tf`), following the same shape as `litellm.tf`.
- **Exposure**: per [[002-networking-and-ingress]], the ingress host `headroom.kms-lab.in.ua` is *not* added to `cloudflare.tf`'s Cloudflare-Tunnel CNAME list. The wildcard `*.kms-lab.in.ua` A-record resolves to the private WG Hub IP (`10.9.0.1`), which isn't internet-routable — so the service is reachable only to devices on the WireGuard VPN, identical to `litellm.kms-lab.in.ua`. No public exposure was added for this service.
- **LiteLLM integration**: rather than building a custom LiteLLM image with the `HeadroomCallback` Python hook (extra image-build/registry overhead), LiteLLM is pointed at Headroom as if it were the upstream OpenAI-compatible provider. The LiteLLM Admin UI hides the `api_base` field when the provider is set to "OpenRouter", so instead the override is set globally via the `OPENROUTER_API_BASE` env var (`http://headroom.default.svc.cluster.local:8787/v1`) on the LiteLLM Deployment in `workload/litellm.tf`, alongside the existing `OPENROUTER_API_KEY`. This still matches the existing decision in [[016-add-litellm-proxy]] to configure models dynamically via the UI rather than in Terraform — only the provider base URL, not model definitions, lives in Terraform.
- **Claude Code integration**: `ANTHROPIC_BASE_URL` is set to `https://headroom.kms-lab.in.ua` in the user's global `~/.claude/settings.json` (outside this repo, machine-level config), verified reachable via the WG tunnel first.
- Headroom forwards upstream using `ANTHROPIC_TARGET_API_URL=https://api.anthropic.com` and `OPENAI_TARGET_API_URL=https://openrouter.ai/api/v1`. It passes through whatever credentials the client supplies rather than holding provider API keys itself.
- **Logging**: the proxy writes no logs unless `--log-file` is passed. `workload/headroom.tf` sets `--log-file /dev/stdout` so JSONL request logs stream to the container's stdout and are visible via `kubectl logs`, matching how other workloads in this repo are observed (no dedicated log-aggregation stack). `--log-messages` (full request/response bodies) was left off to avoid logging payload content by default.
- **Resource limits**: intermittent "API returned an empty or malformed response (HTTP 200)" errors were observed from Claude Code shortly after a headroom pod restart. Investigation showed zero corresponding entries (success or error) in headroom's own request log during the failure windows — the process was dying mid-request, before it could write its completion log line, with no crash visible via `kubectl logs` (stdout only captures the structured JSONL on success) and no restart recorded by kubelet at the time. The container originally had no `resources` block, so a memory spike during heavy compression work could be silently OOM-killed without incrementing the pod's restart count in a way that was caught between checks. `workload/headroom.tf` now sets `requests.memory = 256Mi` / `limits.memory = 1Gi` (and `100m`/`1000m` CPU) to give the ONNX-backed compression pipeline headroom while capping worst-case impact on the node. If the errors recur, check `kubectl describe pod -l app=headroom` for `OOMKilled` and raise the memory limit further.

## Consequences
- Token usage on Claude Code and LiteLLM/OpenRouter traffic should drop significantly on tool-output/JSON-heavy payloads, with no accuracy loss per Headroom's published benchmarks.
- Headroom itself does not authenticate callers — any device already on the WireGuard network could use it as an open relay with its own credentials. This is an accepted risk consistent with how other `*.kms-lab.in.ua` private services are already trusted to WG-connected devices.
- agy (Antigravity) traffic remains uncompressed; revisit if Antigravity CLI ever exposes a supported proxy/base-url configuration.
