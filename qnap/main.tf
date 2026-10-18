terraform {
  backend "gcs" {
    bucket = "terraform-state-actual-budget-server-502619"
    prefix = "terraform/state/qnap"
  }
  required_providers {
    portainer = {
      source  = "portainer/portainer"
      version = "~> 2.0"
    }
    bitwarden-secrets = {
      source  = "registry.terraform.io/bitwarden/bitwarden-secrets"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "bitwarden-secrets" {
  api_url         = "https://api.bitwarden.eu"
  identity_url    = "https://identity.bitwarden.eu"
  organization_id = "dd4d4a61-6bc9-4fce-9f6d-b41b0077db8c"
}

data "bitwarden-secrets_secret" "portainer_token" {
  id = "7e8d123d-5b32-49e0-b4a3-b4e701249afd"
}

data "terraform_remote_state" "workload" {
  backend = "gcs"
  config = {
    bucket = "terraform-state-actual-budget-server-502619"
    prefix = "terraform/state/workload"
  }
}

provider "portainer" {
  endpoint        = "https://portainer.home.arpa"
  api_key         = data.bitwarden-secrets_secret.portainer_token.value
  skip_ssl_verify = true
}

# ==============================================================================
# 1. Portainer SSO (Authentik OIDC) & Administrator Mapping
# ==============================================================================

resource "random_password" "portainer_akadmin_password" {
  length  = 32
  special = false
}

# Pre-create the 'akadmin' administrator account in Portainer CE so that
# when logging in via Authentik OIDC (preferred_username = "akadmin"),
# Portainer maps the session to this Administrator (role = 1) account,
# while preserving the local 'admin' account for emergency internal auth.
resource "portainer_user" "akadmin" {
  username = "akadmin"
  password = random_password.portainer_akadmin_password.result
  role     = 1
}

resource "portainer_settings" "this" {
  authentication_method = 3 # 1 = Internal, 2 = LDAP, 3 = OAuth
  snapshot_interval     = "5m"
  user_session_timeout  = "8h"

  oauth_settings {
    client_id               = "portainer"
    client_secret           = data.terraform_remote_state.workload.outputs.portainer_oidc_client_secret
    authorization_uri       = "https://auth.kms-lab.in.ua/application/o/authorize/"
    access_token_uri        = "https://auth.kms-lab.in.ua/application/o/token/"
    resource_uri            = "https://auth.kms-lab.in.ua/application/o/userinfo/"
    redirect_uri            = "https://portainer.home.arpa"
    logout_uri              = "https://auth.kms-lab.in.ua/application/o/portainer/end-session/"
    user_identifier         = "preferred_username"
    scopes                  = "openid email profile"
    oauth_auto_create_users = true
    sso                     = true
    hide_internal_auth      = false
    auth_style              = 0
  }

  depends_on = [portainer_user.akadmin]
}

# ==============================================================================
# 2. QNAP Docker Compose Stacks (Endpoint ID = 7: local QNAP NAS)
# ==============================================================================

resource "portainer_stack" "traefik" {
  name                      = "traefik"
  deployment_type           = "standalone"
  method                    = "repository"
  endpoint_id               = 7
  repository_url            = "https://github.com/reidMaks/test"
  repository_reference_name = "refs/heads/main"
  file_path_in_repository   = "qnap/traefik/docker-compose.yml"
  update_interval           = "5m"
  tlsskip_verify            = false
  pull_image                = false
  force_update              = false
}

resource "portainer_stack" "arr_suite" {
  name                      = "arr-suite"
  deployment_type           = "standalone"
  method                    = "repository"
  endpoint_id               = 7
  repository_url            = "https://github.com/reidMaks/test"
  repository_reference_name = "refs/heads/main"
  file_path_in_repository   = "qnap/portainer/docker-compose.yml"
  update_interval           = "5m"
  tlsskip_verify            = false
  pull_image                = false
  force_update              = false
}
