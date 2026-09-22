# ==============================================================================
# It's a Plan: AI-Native Issue Tracker & MCP Server
# ==============================================================================

# 1. Namespace
resource "kubernetes_namespace" "management" {
  metadata {
    name = "management"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

# 2. Application & Database Passwords
resource "random_password" "itsaplan_db_password" {
  length  = 32
  special = false
}

resource "random_password" "itsaplan_better_auth_secret" {
  length  = 32
  special = false
}

resource "random_password" "itsaplan_app_encryption_key" {
  length  = 32
  special = false
}

# 3. CloudNativePG (shared-db) Database & Role Provisioning
resource "kubernetes_secret" "itsaplan_db_password_cnpg" {
  metadata {
    name      = "itsaplan-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "itsaplan"
    password = random_password.itsaplan_db_password.result
  }
}

resource "kubernetes_manifest" "itsaplan_role" {
  depends_on = [kubernetes_secret.itsaplan_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "itsaplan"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "itsaplan"
      login = true
      passwordSecret = {
        name = kubernetes_secret.itsaplan_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "itsaplan_database" {
  depends_on = [kubernetes_manifest.itsaplan_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "itsaplan"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "itsaplan"
      owner = "itsaplan"
    }
  }
}

# 4. Declarative MinIO Bucket Initialization (mc Job)
resource "kubernetes_job_v1" "itsaplan_minio_bucket_init" {
  metadata {
    name      = "itsaplan-minio-bucket-init"
    namespace = kubernetes_namespace.management.metadata[0].name
  }

  spec {
    template {
      metadata {
        name = "itsaplan-minio-bucket-init"
      }
      spec {
        restart_policy = "OnFailure"
        container {
          name    = "mc"
          image   = "quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            until mc alias set localminio ${local.minio_s3_endpoint} admin "$MINIO_ROOT_PASSWORD"; do
              echo "Waiting for MinIO..."
              sleep 2
            done
            mc mb --ignore-existing localminio/itsaplan-attachments
            EOT
          ]
          env {
            name  = "MINIO_ROOT_PASSWORD"
            value = data.bitwarden-secrets_secret.minio_root.value
          }
        }
      }
    }
  }
}

# 5. Helm Release: It's a Plan
resource "helm_release" "itsaplan" {
  name            = "itsaplan"
  chart           = "${path.module}/charts/itsaplan"
  namespace       = kubernetes_namespace.management.metadata[0].name
  upgrade_install = true

  values = [
    yamlencode({
      api = {
        image = {
          tag = "1.0.0"
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            memory = "512Mi"
          }
        }
        env = {
          API_URL             = "https://plan-api.kms-lab.in.ua"
          APP_URL             = "https://plan.kms-lab.in.ua"
          COOKIE_DOMAIN       = ".kms-lab.in.ua"
          S3_BUCKET           = "itsaplan-attachments"
          S3_REGION           = "us-east-1"
          S3_FORCE_PATH_STYLE = "true"
          TELEMETRY_DISABLED  = "1"
        }
      }
      web = {
        image = {
          tag = "1.0.0"
        }
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            memory = "512Mi"
          }
        }
      }
      worker = {
        image = {
          tag = "1.0.0"
        }
        resources = {
          requests = {
            cpu    = "20m"
            memory = "64Mi"
          }
          limits = {
            memory = "256Mi"
          }
        }
        env = {
          TELEMETRY_DISABLED = "1"
          DO_NOT_TRACK       = "1"
        }
      }
      bot = {
        enabled = false
      }
      postgresql = {
        enabled = false
      }
      externalDatabase = {
        url = "postgresql://itsaplan:${random_password.itsaplan_db_password.result}@shared-db-rw.cnpg-system.svc.cluster.local:5432/itsaplan"
      }
      minio = {
        enabled = false
      }
      externalS3 = {
        endpoint = local.minio_s3_endpoint
      }
      secrets = {
        postgresPassword  = random_password.itsaplan_db_password.result
        betterAuthSecret  = random_password.itsaplan_better_auth_secret.result
        appEncryptionKey  = random_password.itsaplan_app_encryption_key.result
        s3AccessKeyId     = "admin"
        s3SecretAccessKey = data.bitwarden-secrets_secret.minio_root.value
      }
      ingress = {
        enabled   = true
        className = "traefik"
        host      = "plan.kms-lab.in.ua"
        tls = {
          enabled = false
        }
        api = {
          mode = "separate-host"
          host = "plan-api.kms-lab.in.ua"
          tls = {
            enabled = false
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_manifest.itsaplan_database,
    kubernetes_job_v1.itsaplan_minio_bucket_init
  ]
}
