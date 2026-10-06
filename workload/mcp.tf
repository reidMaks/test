# ==========================================
# In-Cluster MCP Servers for Network Agents
# ==========================================

module "mcp" {
  source = "./mcp"
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
