data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = "terraform-state-actual-budget-server-502619"
    prefix = "terraform/state/infra"
  }
}

data "bitwarden-secrets_secret" "oci_s3_access_key" {
  id = "65cca481-871b-43af-93e0-b49701635b29"
}

data "bitwarden-secrets_secret" "oci_s3_secret_key" {
  id = "6106b013-4724-4c3e-af8e-b4970162dc38"
}

# Загальний Secret з налаштуваннями S3 для всіх томів, що використовують csi-rclone
resource "kubernetes_secret" "oci_s3_rclone_config" {
  metadata {
    name      = "oci-s3-rclone-config"
    namespace = "kube-system"
  }

  data = {
    "s3-provider"          = "Other"
    "s3-access-key-id"     = data.bitwarden-secrets_secret.oci_s3_access_key.value
    "s3-secret-access-key" = data.bitwarden-secrets_secret.oci_s3_secret_key.value
    "s3-endpoint"          = data.terraform_remote_state.infra.outputs.oci_s3_endpoint
    "s3-acl"               = "private"
  }
}

# Копія секрету для default неймспейсу (для міграцій та утиліт)
resource "kubernetes_secret" "oci_s3_rclone_config_default" {
  metadata {
    name      = "oci-s3-rclone-config"
    namespace = "default"
  }

  data = {
    "configData" = <<-EOT
      [oci-s3]
      type = s3
      provider = Other
      access_key_id = ${data.bitwarden-secrets_secret.oci_s3_access_key.value}
      secret_access_key = ${data.bitwarden-secrets_secret.oci_s3_secret_key.value}
      endpoint = ${data.terraform_remote_state.infra.outputs.oci_s3_endpoint}
      acl = private
    EOT
  }
}

# Розгортаємо CSI драйвер через Helm
resource "helm_release" "csi_rclone" {
  name             = "csi-rclone"
  repository       = "https://storage.googleapis.com/charts.wdr.io"
  chart            = "csi-rclone"
  namespace        = "kube-system"
  create_namespace = true

  values = [
    yamlencode({
      params = {
        "s3-provider"          = "Other"
        "s3-endpoint"          = data.terraform_remote_state.infra.outputs.oci_s3_endpoint
        "s3-access-key-id"     = data.bitwarden-secrets_secret.oci_s3_access_key.value
        "s3-secret-access-key" = data.bitwarden-secrets_secret.oci_s3_secret_key.value
        "s3-acl"               = "private"
      }
    })
  ]
}
