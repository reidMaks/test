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
      openrouter_api_key = data.bitwarden-secrets_secret.open_router_api_key.value
      db_password        = random_password.openwebui_db_password.result
      redis_password     = data.bitwarden-secrets_secret.shared_redis.value
    })
  ]
}

resource "random_password" "openwebui_db_password" {
  length  = 32
  special = false
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
    }
  }
}
