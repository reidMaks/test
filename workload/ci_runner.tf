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
      # Privileged PSS is required in 'ci' for the rootless/DinD Docker daemon
      # sidecar inside the global forgejo-runner pod.
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "kubernetes_namespace" "apps" {
  metadata {
    name = "apps"
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

# 3.3 GHCR ImagePullSecret in "apn-prod" (for pulling ghcr.io/reidmaks/apn release images)
resource "kubernetes_secret" "apn_prod_ghcr_secret" {
  metadata {
    name      = "ghcr-secret"
    namespace = kubernetes_namespace.apn_prod.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = "reidmaks"
          password = data.bitwarden-secrets_secret.github_token.value
          auth     = base64encode("reidmaks:${data.bitwarden-secrets_secret.github_token.value}")
        }
      }
    })
  }

  lifecycle {
    # GitHub Actions CD pipeline refreshes ghcr-secret with short-lived ghs_* tokens on deploy
    ignore_changes = [
      data,
      metadata[0].annotations,
    ]
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
          image   = "alpine/k8s:1.36.5"
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

# ==============================================================================
# 6. Global Forgejo Actions Runner (DinD + Multi-Arch QEMU + Scoped K8s RBAC)
# ==============================================================================

resource "kubernetes_service_account" "forgejo_runner" {
  metadata {
    name      = "forgejo-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }
}

# Full Sandbox Autonomy inside "apps" namespace
resource "kubernetes_role" "forgejo_runner_apps" {
  metadata {
    name      = "forgejo-runner-apps-deployer"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "forgejo_runner_apps_binding" {
  metadata {
    name      = "forgejo-runner-apps-binding"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.forgejo_runner_apps.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.forgejo_runner.metadata[0].name
    namespace = kubernetes_service_account.forgejo_runner.metadata[0].namespace
  }
}

# Least-Privilege Rollout Restart Permissions in "default" namespace
resource "kubernetes_role" "forgejo_runner_default_rollout" {
  metadata {
    name      = "forgejo-runner-default-rollout"
    namespace = "default"
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "replicasets"]
    verbs      = ["get", "list", "watch", "patch", "update"]
  }
}

resource "kubernetes_role_binding" "forgejo_runner_default_rollout_binding" {
  metadata {
    name      = "forgejo-runner-default-rollout-binding"
    namespace = "default"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.forgejo_runner_default_rollout.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.forgejo_runner.metadata[0].name
    namespace = kubernetes_service_account.forgejo_runner.metadata[0].namespace
  }
}

resource "kubernetes_secret" "forgejo_runner_config" {
  metadata {
    name      = "forgejo-runner-config"
    namespace = kubernetes_namespace.ci.metadata[0].name
  }

  data = {
    "config.yml" = yamlencode({
      log = {
        level     = "info"
        job_level = "info"
      }
      runner = {
        file             = "/data/.runner"
        capacity         = 2
        timeout          = "1h"
        shutdown_timeout = "15m"
        insecure         = false
        fetch_timeout    = "30s"
        fetch_interval   = "2s"
        report_interval  = "1s"
        labels = [
          "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04",
          "docker:docker://node:22-bookworm"
        ]
      }
      cache = {
        enabled = true
      }
      container = {
        network       = "bridge"
        privileged    = false
        docker_host   = "automount"
        options       = "--add-host=git.kms-lab.in.ua:192.168.0.45 -v /tools:/tools:ro"
        valid_volumes = ["**"]
      }
      server = {
        connections = {
          forgejo = {
            url            = "http://forgejo.default.svc.cluster.local:3000"
            uuid           = local.forgejo_runner_uuid
            token          = local.forgejo_runner_secret
            fetch_interval = "2s"
          }
        }
      }
    })
  }
}

resource "kubernetes_deployment" "forgejo_runner" {
  metadata {
    name      = "forgejo-runner"
    namespace = kubernetes_namespace.ci.metadata[0].name
    labels = {
      app = "forgejo-runner"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "forgejo-runner"
      }
    }

    template {
      metadata {
        labels = {
          app = "forgejo-runner"
        }
        annotations = {
          "checksum/config" = sha256(kubernetes_secret.forgejo_runner_config.data["config.yml"])
        }
      }

      spec {
        service_account_name = kubernetes_service_account.forgejo_runner.metadata[0].name

        node_selector = {
          "topology.kubernetes.io/zone" = "home"
          "kubernetes.io/arch"          = "amd64"
        }

        host_aliases {
          ip        = "192.168.0.45"
          hostnames = ["git.kms-lab.in.ua", "auth.kms-lab.in.ua"]
        }

        # 1. Enable multi-arch QEMU binfmt (arm64 builds for QNAP / TV-Box / OCI)
        init_container {
          name  = "enable-binfmt"
          image = "tonistiigi/binfmt:qemu-v9.2.2"
          args  = ["--install", "arm64"]

          security_context {
            privileged = true
          }
        }

        # 2. Copy kubectl & helm into /tools and prepare /data permissions for UID 1000
        init_container {
          name    = "install-k8s-tools"
          image   = "alpine/k8s:1.36.5"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            set -e
            mkdir -p /tools /data/.cache
            cp "$(command -v helm)" /tools/helm
            cp "$(command -v kubectl)" /tools/kubectl
            chmod +x /tools/kubectl /tools/helm
            chown -R 1000:1000 /data
            EOT
          ]

          volume_mount {
            name       = "tools-bin"
            mount_path = "/tools"
          }

          volume_mount {
            name       = "runner-data"
            mount_path = "/data"
          }
        }

        # Docker-in-Docker sidecar for container builds & Compose tests
        container {
          name  = "dind"
          image = "docker:27-dind"
          args = [
            "dockerd",
            "--group=0",
            "--host=unix:///var/run/docker.sock",
            "--host=tcp://127.0.0.1:2375",
            "--tls=false"
          ]

          security_context {
            privileged = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "docker-sock"
            mount_path = "/var/run"
          }

          volume_mount {
            name       = "docker-graph"
            mount_path = "/var/lib/docker"
          }

          volume_mount {
            name       = "tools-bin"
            mount_path = "/tools"
            read_only  = true
          }
        }

        # Forgejo Actions Runner daemon
        container {
          name    = "runner"
          image   = "data.forgejo.org/forgejo/runner:13.2.1"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            while [ ! -S /var/run/docker.sock ]; do
              sleep 1
            done
            exec forgejo-runner daemon --config /config/config.yml
            EOT
          ]

          security_context {
            run_as_user  = 1000
            run_as_group = 0
          }

          env {
            name  = "DOCKER_HOST"
            value = "unix:///var/run/docker.sock"
          }

          env {
            name  = "PATH"
            value = "/tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "docker-sock"
            mount_path = "/var/run"
          }

          volume_mount {
            name       = "tools-bin"
            mount_path = "/tools"
            read_only  = true
          }

          volume_mount {
            name       = "runner-data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "runner-config"
            mount_path = "/config"
            read_only  = true
          }
        }

        volume {
          name = "docker-sock"
          empty_dir {}
        }

        volume {
          name = "docker-graph"
          empty_dir {}
        }

        volume {
          name = "tools-bin"
          empty_dir {}
        }

        volume {
          name = "runner-data"
          empty_dir {}
        }

        volume {
          name = "runner-config"
          secret {
            secret_name = kubernetes_secret.forgejo_runner_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [helm_release.forgejo]
}
