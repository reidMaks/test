resource "helm_release" "intel_device_plugins_operator" {
  name             = "intel-device-plugins-operator"
  repository       = "https://intel.github.io/helm-charts"
  chart            = "intel-device-plugins-operator"
  namespace        = "kube-system"
  create_namespace = false
  version          = "0.37.0"

  values = [
    yamlencode({
      manager = {
        devices = {
          gpu = true
        }
      }
    })
  ]
}

resource "helm_release" "intel_gpu_plugin" {
  name             = "intel-gpu-plugin"
  repository       = "https://intel.github.io/helm-charts"
  chart            = "intel-device-plugins-gpu"
  namespace        = "kube-system"
  create_namespace = false
  version          = "0.37.0"

  depends_on = [helm_release.intel_device_plugins_operator]

  values = [
    yamlencode({
      nodeFeatureRule = false
      sharedDevNum    = 5
    })
  ]
}

# ---------------------------------------------------------------------------
# Watchdog для intel-gpu-plugin
#
# Чому не звичайний livenessProbe на DaemonSet: DS повністю належить оператору
# (ownerReference -> GpuDevicePlugin/gpudeviceplugin-sample), а CRD не має полів
# ані для проб, ані для проброса pod spec -- будь-який ручний патч оператор
# відкотить. До того ж образ intel/intel-gpu-plugin distroless (немає /bin/sh,
# тож exec-проба неможлива), а плагін слухає лише unix-сокети в
# /var/lib/kubelet/device-plugins/ і не має ні HTTP, ні TCP порту -- httpGet і
# tcpSocket теж нікуди підключити.
#
# Тому пробу винесено назовні: CronJob звіряє те, що бачить kubelet
# (allocatable gpu.intel.com/i915), з тим, що под плагіна живий. Саме ця
# розбіжність поклала Immich на 4.5 доби 03.09.2026 -- процес плагіна не падав,
# але девайси для kubelet стали unhealthy, і поди із запитом i915 не проходили
# admission з UnexpectedAdmissionError.
# ---------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "intel_gpu_plugin_watchdog" {
  metadata {
    name      = "intel-gpu-plugin-watchdog"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_v1" "intel_gpu_plugin_watchdog" {
  metadata {
    name = "intel-gpu-plugin-watchdog"
  }

  # nodes -- щоб прочитати status.allocatable по GPU-нодах.
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list"]
  }

  # pods -- знайти под плагіна і перезапустити його, а також прибрати поди,
  # які kubelet відкинув через недоступний GPU (вони лишаються у фазі Failed
  # назавжди). Delete потрібен cluster-wide, бо споживачі i915 живуть у default,
  # а сам плагін -- у kube-system.
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "delete"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "intel_gpu_plugin_watchdog" {
  metadata {
    name = "intel-gpu-plugin-watchdog"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.intel_gpu_plugin_watchdog.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.intel_gpu_plugin_watchdog.metadata[0].name
    namespace = "kube-system"
  }
}

resource "kubernetes_cron_job_v1" "intel_gpu_plugin_watchdog" {
  metadata {
    name      = "intel-gpu-plugin-watchdog"
    namespace = "kube-system"
  }

  spec {
    schedule                      = "*/10 * * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3
    starting_deadline_seconds     = 120

    job_template {
      metadata {}
      spec {
        backoff_limit = 1
        template {
          metadata {}
          spec {
            service_account_name = kubernetes_service_account_v1.intel_gpu_plugin_watchdog.metadata[0].name
            restart_policy       = "Never"

            # GPU-нода і споживачі i915 (Immich) живуть лише в домашній зоні.
            node_selector = {
              "topology.kubernetes.io/zone" = "home"
            }

            container {
              name  = "watchdog"
              image = "alpine/k8s:1.36.1"

              resources {
                requests = {
                  cpu    = "10m"
                  memory = "32Mi"
                }
                limits = {
                  memory = "64Mi"
                }
              }

              command = ["/bin/sh", "-c"]
              args = [<<-EOT
                set -eu

                GRACE_SECONDS=300

                # Скільки секунд поду. Якщо розпарсити час не вдалось -- вважаємо
                # под старим, щоб watchdog не замовк через формат дати.
                pod_age() {
                  # RFC3339 -> "YYYY-MM-DD hh:mm:ss": busybox date не розуміє
                  # роздільник T і суфікс Z. Далі пробуємо спершу синтаксис GNU,
                  # потім busybox (-D), щоб не залежати від збірки образу.
                  ts="$(echo "$1" | tr 'T' ' ' | tr -d 'Z')"
                  now="$(date -u +%s)"
                  start="$(date -u -d "$ts" +%s 2>/dev/null || date -u -D '%Y-%m-%d %H:%M:%S' -d "$ts" +%s 2>/dev/null || echo '')"
                  if [ -z "$start" ]; then
                    echo 999999
                  else
                    echo "$((now - start))"
                  fi
                }

                for node in $(kubectl get nodes -l intel.feature.node.kubernetes.io/gpu=true -o jsonpath='{.items[*].metadata.name}'); do
                  alloc="$(kubectl get node "$node" -o jsonpath='{.status.allocatable.gpu\.intel\.com/i915}' 2>/dev/null || echo '')"
                  case "$alloc" in
                    '' | *[!0-9]*) alloc=0 ;;
                  esac

                  if [ "$alloc" -gt 0 ]; then
                    echo "node/$node: i915 allocatable=$alloc, healthy"
                    continue
                  fi

                  pod="$(kubectl get pods -n kube-system -l app=intel-gpu-plugin \
                    --field-selector "spec.nodeName=$node,status.phase=Running" \
                    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo '')"

                  if [ -z "$pod" ]; then
                    echo "node/$node: i915 allocatable=0, no Running plugin pod -- DaemonSet handles it"
                    continue
                  fi

                  # Саме час поточного інстансу контейнера, а не поду: контейнер
                  # плагіна перезапускається окремо, і після рестарту йому знову
                  # потрібні секунди на реєстрацію девайсів.
                  started="$(kubectl get pod -n kube-system "$pod" -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null || echo '')"
                  if [ -z "$started" ]; then
                    echo "node/$node: i915 allocatable=0, pod/$pod has no running container -- kubelet handles it"
                    continue
                  fi

                  age="$(pod_age "$started")"
                  if [ "$age" -lt "$GRACE_SECONDS" ]; then
                    echo "node/$node: i915 allocatable=0, pod/$pod is $age s old -- still registering"
                    continue
                  fi

                  echo "node/$node: i915 allocatable=0 while pod/$pod has been running $age s -- plugin is hung, restarting"
                  kubectl delete pod -n kube-system "$pod"
                done

                # Поди, відкинуті kubelet поки GPU був недоступний, залишаються у
                # фазі Failed назавжди. Прибираємо їх.
                kubectl get pods -A --field-selector status.phase=Failed \
                  -o jsonpath='{range .items[?(@.status.reason=="UnexpectedAdmissionError")]}{.metadata.namespace} {.metadata.name}{"\n"}{end}' \
                  | while read -r ns name; do
                      [ -n "$name" ] || continue
                      echo "cleaning up rejected pod $ns/$name"
                      kubectl delete pod -n "$ns" "$name" --ignore-not-found
                    done
              EOT
              ]
            }
          }
        }
      }
    }
  }
}
