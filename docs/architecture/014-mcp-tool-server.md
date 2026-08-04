# ADR 014: MCP Tool Server for Open WebUI

## Status
Accepted

## Context
We deployed Open WebUI to interact with LLMs. To enhance the capabilities of agents within Open WebUI, we need to provide them with tools via the Model Context Protocol (MCP). Specifically, we want agents to be able to query the Kubernetes cluster state and potentially Prometheus metrics.

Open WebUI acts as an OpenAPI client. To bridge stdio-based MCP servers (which most community servers are) to Open WebUI, the recommended approach is using `MCPO` (MCP-to-OpenAPI proxy).

## Decision
1. **Tool Server Proxy**: We will deploy a dedicated Kubernetes Pod running the `ghcr.io/open-webui/mcpo:main` image to act as our Tool Server proxy.
2. **Dynamic Tool Execution**: Since the MCPO image is Python-based and includes `uvx`, we can define our MCP servers in a `config.json` file and run them directly using `uvx` (e.g., `uvx mcp-server-time` or `uvx mcp-kubernetes-server`).
3. **Read-Only Kubernetes Access**: To allow the Kubernetes MCP to query the cluster, the MCPO Pod is assigned a specific `ServiceAccount` bound to a `ClusterRole` that grants read-only access (`get`, `list`, `watch`) across the cluster.
4. **Configuration**: The configuration for the MCP servers is managed via a Kubernetes `ConfigMap` mounted into the MCPO Pod.

## Consequences
- **Security**: The Kubernetes MCP runs with in-cluster credentials. By explicitly limiting the `ClusterRole` to read-only verbs, we prevent agents from accidentally or maliciously modifying the cluster state.
- **Extensibility**: Adding new tools is as simple as updating the `ConfigMap` and restarting the MCPO Pod. Python-based tools can be dynamically fetched by `uvx`. For Node-based tools (requiring `npx`), a custom Docker image might be required in the future.
- **Integration**: The MCPO service is exposed internally and can be added in Open WebUI's admin panel as an OpenAPI tool server at `http://mcpo-service.default.svc.cluster.local:8000/openapi.json`.
