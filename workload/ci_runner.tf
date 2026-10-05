# ==============================================================================
# GitHub Actions Self-Hosted Runner & Ephemeral Preview Isolation
# Provides in-cluster CI runner with RBAC strictly scoped to "apn-preview"
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

# 2. ServiceAccount for GitHub Actions Runner in "ci" namespace
resource "kubernetes_service_account" "github_runner" {
  metadata {
    name      = "github-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}

# 3. RBAC: Strict Least-Privilege Role in "apn-preview"
resource "kubernetes_role" "apn_preview_deployer" {
  metadata {
    name      = "apn-preview-deployer"
    namespace = kubernetes_namespace.apn_preview.metadata[0].name
  }

  rule {
    api_groups = ["", "apps", "batch", "networking.k8s.io"]
    resources = [
      "pods",
      "pods/log",
      "pods/exec",
      "services",
      "endpoints",
      "persistentvolumeclaims",
      "configmaps",
      "secrets",
      "deployments",
      "statefulsets",
      "replicasets",
      "jobs",
      "ingresses"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete", "deletecollection"]
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

# 3.1 RBAC: Scoped Staging Deployment Role in "apn" (APN-134 CD)
resource "kubernetes_role" "github_runner_apn_staging" {
  metadata {
    name      = "github-runner-apn-staging"
    namespace = kubernetes_namespace.apn.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "patch", "update"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create", "get"]
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

        # Init container to install kubectl and helm into shared volume
        init_container {
          name    = "install-k8s-tools"
          image   = "alpine/helm:3.17.1"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            set -e
            mkdir -p /tools
            cp /usr/bin/helm /tools/helm
            # Download matching kubectl
            wget -q https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl -O /tools/kubectl
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
