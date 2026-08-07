# Backlog & Future Tasks

- [ ] **Kubernetes MCP Server Integration**: Organize and configure an MCP (Model Context Protocol) server specifically for cluster exploration and troubleshooting. This will provide AI agents with native, structured access to cluster state (pods, logs, events, resources) to autonomously investigate and resolve issues without relying solely on manual `kubectl` commands.
- [ ] **Open WebUI: LLM Model Selection & Cost Routing**:
  - Investigate solutions for displaying model prices or implementing an automated routing proxy (e.g., LiteLLM) to select the best OpenRouter model within specific price ranges automatically.
  - Evaluate and select default models for different sub-agents based on cost/performance tradeoffs.
- [ ] **Open WebUI: Cross-lingual RAG & Vector Search Optimization**:
  - Investigate embedding models (e.g., multilingual embeddings) to improve vector search when querying an English knowledge base using Ukrainian prompts.
  - Research options for tuning vector search mechanisms in Open WebUI to return more relevant and less limited context.
- [ ] **Open WebUI: Prompt Translation & Enhancement Adapter**:
  - Create a custom Filter Function in Open WebUI to automatically translate and enhance Ukrainian user prompts into high-quality English before executing the RAG vector search, ensuring perfect alignment with the English documentation.
- [ ] **Documentation Alignment**: Ensure all project documentation is fully translated/maintained in English (as required by project rules) to maximize RAG effectiveness.
