# ==========================================
# In-Cluster MCP Servers for Network Agents
# ==========================================

data "bitwarden-secrets_secret" "portainer_token" {
  id = "7e8d123d-5b32-49e0-b4a3-b4e701249afd"
}

resource "random_password" "portainer_mcp_gate_token" {
  length  = 64
  special = false
}

module "mcp" {
  source                   = "./mcp"
  portainer_api_key        = data.bitwarden-secrets_secret.portainer_token.value
  portainer_mcp_gate_token = random_password.portainer_mcp_gate_token.result
}

output "mcp_k8s_endpoint" {
  description = "Kubernetes MCP server endpoint"
  value       = module.mcp.k8s_mcp_endpoint
}

output "mcp_prometheus_endpoint" {
  description = "Prometheus MCP server endpoint"
  value       = module.mcp.prom_mcp_endpoint
}

output "mcp_grafana_endpoint" {
  description = "Grafana MCP server endpoint"
  value       = module.mcp.grafana_mcp_endpoint
}

output "mcp_paperless_endpoint" {
  description = "Paperless-ngx MCP server endpoint"
  value       = module.mcp.paperless_mcp_endpoint
}

output "mcp_portainer_endpoint" {
  description = "Portainer MCP server endpoint"
  value       = module.mcp.portainer_mcp_endpoint
}
