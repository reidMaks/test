terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
  }
}
