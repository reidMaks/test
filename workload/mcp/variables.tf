variable "k8s_mcp_host" {
  type        = string
  description = "Ingress hostname for Kubernetes MCP server"
  default     = "k8s-mcp.kms-lab.in.ua"
}

variable "prom_mcp_host" {
  type        = string
  description = "Ingress hostname for Prometheus MCP server"
  default     = "prom-mcp.kms-lab.in.ua"
}

variable "prometheus_url" {
  type        = string
  description = "Internal URL to VictoriaMetrics / Prometheus server"
  default     = "http://vmsingle-vm-victoria-metrics-k8s-stack.monitoring.svc.cluster.local:8428"
}

variable "grafana_mcp_host" {
  type        = string
  description = "Ingress hostname for Grafana MCP server"
  default     = "grafana-mcp.kms-lab.in.ua"
}

variable "grafana_internal_url" {
  type        = string
  description = "Internal URL to Grafana"
  default     = "http://vm-grafana.monitoring.svc.cluster.local:80"
}
