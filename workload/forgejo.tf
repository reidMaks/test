# ==============================================================================
# Forgejo: Self-Hosted Git Server, OCI Container Registry & CI/CD Coordinator
# ==============================================================================

resource "random_password" "forgejo_db_password" {
  length  = 32
  special = false
}

resource "random_password" "forgejo_admin_password" {
  length  = 24
  special = false
}

resource "random_password" "forgejo_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "forgejo_internal_token" {
  length  = 64
  special = false
}

# 24-hex-char random suffix combined with fixed 16-hex-char prefix ("4b4d534c4142524e" = "KMSLABRN")
# yields a deterministic 40-hex-char secret for `forgejo-cli actions register --secret`
# whose derived runner UUID is always "34623464-3533-3463-3431-343235323465".
resource "random_id" "forgejo_runner_secret_tail" {
  byte_length = 12
}

locals {
  forgejo_runner_uuid   = "34623464-3533-3463-3431-343235323465"
  forgejo_runner_secret = "4b4d534c4142524e${random_id.forgejo_runner_secret_tail.hex}"
}

resource "kubernetes_secret" "forgejo" {
  metadata {
    name      = "forgejo-secrets"
    namespace = "default"
  }

  data = {
    FORGEJO__database__PASSWD         = random_password.forgejo_db_password.result
    FORGEJO__security__SECRET_KEY     = random_password.forgejo_secret_key.result
    FORGEJO__security__INTERNAL_TOKEN = random_password.forgejo_internal_token.result
    FORGEJO_ADMIN_PASSWORD            = random_password.forgejo_admin_password.result
    FORGEJO_OIDC_CLIENT_SECRET        = random_password.authentik_forgejo_secret.result
    FORGEJO_RUNNER_SECRET             = local.forgejo_runner_secret
  }
}

# CloudNativePG (shared-db) Database & Role Provisioning
resource "kubernetes_secret" "forgejo_db_password_cnpg" {
  metadata {
    name      = "forgejo-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "forgejo"
    password = random_password.forgejo_db_password.result
  }
}

resource "kubernetes_manifest" "forgejo_role" {
  depends_on = [kubernetes_secret.forgejo_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "forgejo"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "forgejo"
      login = true
      passwordSecret = {
        name = kubernetes_secret.forgejo_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "forgejo_database" {
  depends_on = [kubernetes_manifest.forgejo_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "forgejo"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "forgejo"
      owner = "forgejo"
    }
  }
}

resource "kubernetes_persistent_volume_claim" "forgejo_git" {
  metadata {
    name      = "forgejo-git"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
  depends_on = [helm_release.longhorn]
}

resource "kubernetes_persistent_volume_claim" "forgejo_packages" {
  metadata {
    name      = "forgejo-packages"
    namespace = "default"
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.longhorn_postgres.metadata[0].name
    resources {
      requests = {
        storage = "3Gi"
      }
    }
  }
}

resource "helm_release" "forgejo" {
  name            = "forgejo"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = local.app_template_version
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/forgejo.yaml")
  ]

  depends_on = [
    kubernetes_secret.forgejo,
    kubernetes_manifest.forgejo_database,
    kubernetes_persistent_volume_claim.forgejo_git,
    kubernetes_persistent_volume_claim.forgejo_packages,
    helm_release.authentik
  ]
}

# Traefik TCP Routing for Git SSH (Port 22 -> forgejo:22)
resource "kubernetes_manifest" "forgejo_ssh_ingressroute" {
  depends_on = [
    helm_release.traefik,
    helm_release.forgejo
  ]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"
    metadata = {
      name      = "forgejo-ssh"
      namespace = "default"
    }
    spec = {
      entryPoints = ["git-ssh"]
      routes = [
        {
          match = "HostSNI(`*`)"
          services = [
            {
              name = "forgejo"
              port = 22
            }
          ]
        }
      ]
    }
  }
}

# Attach Longhorn 3-2-1 daily backup label ONLY to the Git repository volume (forgejo-git),
# leaving forgejo-packages (Docker image blobs & CI artifacts) out of cloud backups.
resource "kubernetes_labels" "longhorn_backup_forgejo_git" {
  api_version = "longhorn.io/v1beta2"
  kind        = "Volume"
  metadata {
    name      = kubernetes_persistent_volume_claim.forgejo_git.spec[0].volume_name
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
  }
  labels = {
    "recurring-job-group.longhorn.io/daily-backups" = "enabled"
  }

  depends_on = [
    kubernetes_persistent_volume_claim.forgejo_git,
    kubernetes_manifest.longhorn_daily_backup
  ]
}
