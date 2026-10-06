output "k8s_mcp_endpoint" {
  description = "Streamable HTTP endpoint for Kubernetes MCP server"
  value       = "http://${var.k8s_mcp_host}/mcp"
}

output "prom_mcp_endpoint" {
  description = "Streamable HTTP endpoint for Prometheus MCP server"
  value       = "http://${var.prom_mcp_host}/mcp"
}

output "grafana_mcp_endpoint" {
  description = "Streamable HTTP endpoint for Grafana MCP server"
  value       = "http://${var.grafana_mcp_host}/mcp"
}
