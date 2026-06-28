terraform {
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

provider "bitwarden-secrets" {
  api_url         = "https://api.bitwarden.eu"
  identity_url    = "https://identity.bitwarden.eu"
  access_token    = var.bitwarden_token
  organization_id = "dd4d4a61-6bc9-4fce-9f6d-b41b0077db8c"
}
