# ==============================================================================
# GitHub Actions Self-Hosted Runner & Isolated APN Sandbox Namespaces
# Provides in-cluster CI runner & ServiceAccount with full RBAC strictly scoped
# to APN namespaces ("apn", "apn-preview", "apn-prod") and zero cluster access.
# ==============================================================================

# 1. Namespaces
resource "kubernetes_namespace" "ci" {
  metadata {
    name = "ci"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

resource "kubernetes_namespace" "apn" {
  metadata {
    name = "apn"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

resource "kubernetes_namespace" "apn_preview" {
  metadata {
    name = "apn-preview"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

resource "kubernetes_namespace" "apn_prod" {
  metadata {
    name = "apn-prod"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

# 2. ServiceAccount & Token for APN Deployer / GitHub Actions Runner in "ci"
resource "kubernetes_service_account" "github_runner" {
  metadata {
    name      = "github-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}

resource "kubernetes_secret_v1" "apn_deployer_token" {
  metadata {
    name      = "apn-deployer-token"
    namespace = kubernetes_namespace.ci.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.github_runner.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# 3. RBAC: Full Sandbox Autonomy strictly inside "apn-preview"
resource "kubernetes_role" "apn_preview_deployer" {
  metadata {
    name      = "apn-preview-deployer"
    namespace = kubernetes_namespace.apn_preview.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "github_runner_preview_binding" {
  metadata {
    name      = "github-runner-preview-binding"
    namespace = kubernetes_namespace.apn_preview.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.apn_preview_deployer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.github_runner.metadata[0].name
    namespace = kubernetes_service_account.github_runner.metadata[0].namespace
  }
}

# 3.1 RBAC: Full Sandbox Autonomy strictly inside "apn" (Staging)
resource "kubernetes_role" "github_runner_apn_staging" {
  metadata {
    name      = "github-runner-apn-staging"
    namespace = kubernetes_namespace.apn.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "github_runner_apn_staging_binding" {
  metadata {
    name      = "github-runner-apn-staging-binding"
    namespace = kubernetes_namespace.apn.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.github_runner_apn_staging.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.github_runner.metadata[0].name
    namespace = kubernetes_service_account.github_runner.metadata[0].namespace
  }
}

# 3.2 RBAC: Full Sandbox Autonomy strictly inside "apn-prod" (Production)
resource "kubernetes_role" "github_runner_apn_prod" {
  metadata {
    name      = "github-runner-apn-prod"
    namespace = kubernetes_namespace.apn_prod.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "github_runner_apn_prod_binding" {
  metadata {
    name      = "github-runner-apn-prod-binding"
    namespace = kubernetes_namespace.apn_prod.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.github_runner_apn_prod.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.github_runner.metadata[0].name
    namespace = kubernetes_service_account.github_runner.metadata[0].namespace
  }
}

# 4. GitHub Runner Secret (Uses Bitwarden Secret github_token)
resource "kubernetes_secret" "github_runner_token" {
  metadata {
    name      = "github-runner-token"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  data = {
    ACCESS_TOKEN = data.bitwarden-secrets_secret.github_token.value
  }
}

# 5. GitHub Actions Runner Deployment
resource "kubernetes_deployment" "github_runner" {
  metadata {
    name      = "apn-github-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
    labels = {
      app = "apn-github-runner"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "apn-github-runner"
      }
    }

    template {
      metadata {
        labels = {
          app = "apn-github-runner"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.github_runner.metadata[0].name

        node_selector = {
          "topology.kubernetes.io/zone" = "home"
          "kubernetes.io/arch"          = "amd64"
        }

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = {
              app = "apn-github-runner"
            }
          }
        }

        # Init container to copy kubectl and helm from alpine/k8s image into shared volume
        init_container {
          name    = "install-k8s-tools"
          image   = "alpine/k8s:1.36.1"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            set -e
            mkdir -p /tools
            cp "$(command -v helm)" /tools/helm
            cp "$(command -v kubectl)" /tools/kubectl
            chmod +x /tools/kubectl /tools/helm
            EOT
          ]

          volume_mount {
            name       = "tools-bin"
            mount_path = "/tools"
          }
        }

        container {
          name  = "runner"
          image = "myoung34/github-runner:ubuntu-noble"

          env {
            name  = "REPO_URL"
            value = "https://github.com/reidMaks/APN"
          }

          env {
            name  = "RUNNER_NAME_PREFIX"
            value = "talos-apn-k8s"
          }

          env {
            name  = "RANDOM_RUNNER_SUFFIX"
            value = "true"
          }

          env {
            name  = "LABELS"
            value = "self-hosted,linux,apn-k8s,apn-runner"
          }

          env {
            name = "ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.github_runner_token.metadata[0].name
                key  = "ACCESS_TOKEN"
              }
            }
          }

          # Prepend /tools to PATH so workflow steps can immediately use kubectl & helm
          env {
            name  = "PATH"
            value = "/tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
          }

          volume_mount {
            name       = "tools-bin"
            mount_path = "/tools"
          }

          volume_mount {
            name       = "runner-work"
            mount_path = "/_work"
          }
        }

        volume {
          name = "tools-bin"
          empty_dir {}
        }

        volume {
          name = "runner-work"
          empty_dir {}
        }
      }
    }
  }
}
