terraform {
  backend "gcs" {
    bucket = "terraform-state-actual-budget-server-502619"
    prefix = "terraform/state/workload"
  }
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30.0"
    }
    bitwarden-secrets = {
      source = "registry.terraform.io/bitwarden/bitwarden-secrets"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
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

data "bitwarden-secrets_secret" "cloudflare_api_token" {
  id = "d2256848-eef6-411c-a864-b49300adc052"
}

provider "cloudflare" {
  api_token = data.bitwarden-secrets_secret.cloudflare_api_token.value
}
