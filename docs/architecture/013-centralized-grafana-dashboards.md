# Centralized Grafana Dashboards and Redis Monitoring

## Context
The infrastructure relies on VictoriaMetrics (specifically the `victoria-metrics-k8s-stack` Helm chart) which bundles Grafana for observability. Historically, Grafana dashboard configuration logic (such as ConfigMaps containing the dashboard JSON) was placed inside the respective application's `.tf` file (e.g., `cnpg.tf`).
Additionally, some core infrastructure components, like the shared Redis instance, lacked monitoring configurations and dashboards, meaning that resource utilization and performance metrics were unavailable to cluster operators.

## Decision
1. **Centralize Dashboards:** Keep all Grafana dashboard provisioning centralized rather than spreading it across individual service definitions. A new file `grafana_dashboards.tf` has been created, and all JSON definitions are stored in the `grafana_dashboards/` directory.
2. **Add Redis Monitoring:** To gather telemetry from the shared Redis instance, we appended the `oliver006/redis_exporter` as a sidecar container to the Redis `app-template` Helm release.
3. **Scraping Configuration:** We leverage `VMServiceScrape` (part of the VictoriaMetrics Operator) to automatically scrape the Redis metrics endpoint.
4. **Provision Redis Dashboard:** A standard Redis dashboard was imported and provisioned centrally using a ConfigMap tagged with `grafana_dashboard = "1"`.

## Consequences
- **Positive:** Improved maintainability since all Grafana visualization assets are located in one place.
- **Positive:** Better visibility into Redis cache usage, cache hit ratios, and memory footprints.
- **Negative:** Slightly diverges from the pattern of keeping everything related to a workload inside its own file, but aligns better with how observability as a cross-cutting concern is usually managed.
