locals {
  minio_s3_endpoint = "http://minio.default.svc.cluster.local:9000"

  # renovate: datasource=helm depName=app-template registryUrl=https://bjw-s-labs.github.io/helm-charts
  app_template_version = "5.3.0"
}
