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

variable "paperless_mcp_host" {
  type        = string
  description = "Ingress hostname for Paperless-ngx MCP server"
  default     = "paperless-mcp.kms-lab.in.ua"
}

variable "paperless_internal_url" {
  type        = string
  description = "Internal URL to Paperless-ngx service"
  default     = "http://paperless.default.svc.cluster.local:8000"
}

variable "paperless_public_url" {
  type        = string
  description = "Public URL to Paperless-ngx for user-facing links"
  default     = "https://paperless.kms-lab.in.ua"
}
