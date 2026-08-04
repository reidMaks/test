resource "kubernetes_config_map" "cnpg_grafana_dashboard" {
  metadata {
    name      = "cnpg-grafana-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "cnpg-dashboard.json" = file("${path.module}/grafana_dashboards/cnpg-dashboard.json")
  }
}

resource "kubernetes_config_map" "redis_grafana_dashboard" {
  metadata {
    name      = "redis-grafana-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "redis-dashboard.json" = file("${path.module}/grafana_dashboards/redis-dashboard.json")
  }
}

resource "kubernetes_config_map" "nodes_grafana_dashboard" {
  metadata {
    name      = "nodes-grafana-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "nodes-dashboard.json" = file("${path.module}/grafana_dashboards/nodes-dashboard.json")
  }
}
