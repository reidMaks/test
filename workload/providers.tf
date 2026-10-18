terraform {
  backend "gcs" {
    bucket = "terraform-state-actual-budget-server-502619"
    prefix = "terraform/state/workload"
  }
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    bitwarden-secrets = {
      source  = "registry.terraform.io/bitwarden/bitwarden-secrets"
      version = "~> 1.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
    portainer = {
      source  = "portainer/portainer"
      version = "~> 2.0"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path = "../infra/kubeconfig"
  }
}

provider "kubernetes" {
  config_path = "../infra/kubeconfig"
}

provider "grafana" {
  url  = "https://grafana.kms-lab.in.ua"
  auth = "admin:${data.bitwarden-secrets_secret.grafana_admin_password.value}"
}

data "bitwarden-secrets_secret" "portainer_token" {
  id = "7e8d123d-5b32-49e0-b4a3-b4e701249afd"
}

provider "portainer" {
  endpoint        = "https://portainer.home.arpa"
  api_key         = data.bitwarden-secrets_secret.portainer_token.value
  skip_ssl_verify = true
}

data "bitwarden-secrets_secret" "cloudflare_api_token" {
  id = "d2256848-eef6-411c-a864-b49300adc052"
}

provider "cloudflare" {
  api_token = data.bitwarden-secrets_secret.cloudflare_api_token.value
}
