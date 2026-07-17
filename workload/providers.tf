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
