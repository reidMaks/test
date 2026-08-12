# ==========================================
# OPEN WEBUI (via Helm Chart)
# ==========================================

resource "helm_release" "open_webui" {
  name            = "open-webui"
  repository      = "https://helm.openwebui.com/"
  chart           = "open-webui"
  namespace       = "default"
  upgrade_install = true

  values = [
    templatefile("${path.module}/helm_values/open-webui.yaml", {
      db_password    = random_password.openwebui_db_password.result
      redis_password = data.bitwarden-secrets_secret.shared_redis.value
    })
  ]
}

resource "random_password" "openwebui_db_password" {
  length  = 32
  special = false
}

# WEBUI_SECRET_KEY: with replicaCount > 1 and persistence disabled, each pod would
# otherwise generate its own random JWT signing key at startup, causing "Session
# expired" whenever Traefik routes a request to a different pod than the one that
# issued the session. Must be identical and stable across all replicas.
# NOTE: a secret named "open-webui-secret-key" with the same key/value shape was
# already created manually in-cluster (kubectl) to unblock replicaCount=2 before
# this Terraform change could be applied (no Bitwarden token available in that
# session). Reconcile by importing it or letting this resource replace it:
#   terraform import kubernetes_secret.openwebui_secret_key default/open-webui-secret-key
resource "random_password" "openwebui_secret_key" {
  length  = 64
  special = false
}

resource "kubernetes_secret" "openwebui_secret_key" {
  metadata {
    name      = "open-webui-secret-key"
    namespace = "default"
  }
  data = {
    WEBUI_SECRET_KEY = random_password.openwebui_secret_key.result
  }
}

resource "kubernetes_secret" "openwebui_db_password_cnpg" {
  metadata {
    name      = "openwebui-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "openwebui"
    password = random_password.openwebui_db_password.result
  }
}

resource "kubernetes_manifest" "openwebui_role" {
  depends_on = [kubernetes_secret.openwebui_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "openwebui"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "openwebui"
      login = true
      passwordSecret = {
        name = kubernetes_secret.openwebui_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "openwebui_database" {
  depends_on = [kubernetes_manifest.openwebui_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "openwebui"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "openwebui"
      owner = "openwebui"
      extensions = [
        {
          name = "vector"
        }
      ]
    }
  }
}
