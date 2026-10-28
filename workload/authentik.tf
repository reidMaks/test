# ==============================================================================
# Authentik: Self-Hosted SSO & Identity Provider (IdP)
# ==============================================================================

resource "random_password" "authentik_db_password" {
  length  = 32
  special = false
}

resource "random_password" "authentik_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "authentik_paperless_secret" {
  length  = 48
  special = false
}

resource "random_password" "authentik_grafana_secret" {
  length  = 48
  special = false
}

resource "random_password" "authentik_immich_secret" {
  length  = 48
  special = false
}

resource "random_password" "authentik_portainer_secret" {
  length  = 48
  special = false
}

resource "random_password" "authentik_actual_secret" {
  length  = 48
  special = false
}

resource "random_password" "authentik_rustfs_secret" {
  length  = 48
  special = false
}

resource "random_password" "authentik_forgejo_secret" {
  length  = 48
  special = false
}

resource "random_password" "authentik_rustdesk_secret" {
  length  = 48
  special = false
}

output "portainer_oidc_client_secret" {
  value       = random_password.authentik_portainer_secret.result
  sensitive   = true
  description = "OIDC Client Secret for Portainer on QNAP"
}

resource "kubernetes_secret" "authentik_blueprints" {
  metadata {
    name      = "authentik-blueprints"
    namespace = "default"
  }

  data = {
    "kms-lab-apps.yaml" = templatefile("${path.module}/helm_values/authentik_blueprint.yaml", {
      paperless_client_secret = random_password.authentik_paperless_secret.result
      grafana_client_secret   = random_password.authentik_grafana_secret.result
      immich_client_secret    = random_password.authentik_immich_secret.result
      portainer_client_secret = random_password.authentik_portainer_secret.result
      actual_client_secret    = random_password.authentik_actual_secret.result
      rustfs_client_secret    = random_password.authentik_rustfs_secret.result
      forgejo_client_secret   = random_password.authentik_forgejo_secret.result
      rustdesk_client_secret  = random_password.authentik_rustdesk_secret.result
    })
  }
}

# CloudNativePG (shared-db) Database & Role Provisioning
resource "kubernetes_secret" "authentik_db_password_cnpg" {
  metadata {
    name      = "authentik-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "authentik"
    password = random_password.authentik_db_password.result
  }
}

resource "kubernetes_manifest" "authentik_role" {
  depends_on = [kubernetes_secret.authentik_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "authentik"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "authentik"
      login = true
      passwordSecret = {
        name = kubernetes_secret.authentik_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "authentik_database" {
  depends_on = [kubernetes_manifest.authentik_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "authentik"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "authentik"
      owner = "authentik"
    }
  }
}

resource "helm_release" "authentik" {
  name            = "authentik"
  repository      = "https://charts.goauthentik.io"
  chart           = "authentik"
  version         = "2026.8.4"
  namespace       = "default"
  upgrade_install = true
  timeout         = 600

  values = [
    templatefile("${path.module}/helm_values/authentik.yaml", {
      db_password        = random_password.authentik_db_password.result
      secret_key         = random_password.authentik_secret_key.result
      blueprint_checksum = sha256(kubernetes_secret.authentik_blueprints.data["kms-lab-apps.yaml"])
    })
  ]

  depends_on = [
    kubernetes_manifest.authentik_database,
    kubernetes_secret.authentik_blueprints
  ]
}

# Pre-provisioned Traefik ForwardAuth Middleware (inactive until attached to an Ingress annotation)
resource "kubernetes_manifest" "traefik_middleware_authentik" {
  depends_on = [helm_release.authentik]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "authentik-forwardauth"
      namespace = "default"
    }
    spec = {
      forwardAuth = {
        address            = "http://authentik-server.default.svc.cluster.local:80/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader = true
        authResponseHeaders = [
          "X-authentik-username",
          "X-authentik-groups",
          "X-authentik-entitlements",
          "X-authentik-email",
          "X-authentik-name",
          "X-authentik-uid",
          "X-authentik-jwt",
          "X-authentik-meta-jwks",
          "X-authentik-meta-outpost",
          "X-authentik-meta-provider",
          "X-authentik-meta-app",
          "X-authentik-meta-version"
        ]
      }
    }
  }
}
