# ==========================================
# ГЕНЕРАЦІЯ КОНФІГУРАЦІЇ ДЛЯ CONTROL PLANE
# ==========================================

data "talos_machine_configuration" "cp_config" {
  cluster_name     = "talos-k8s"
  cluster_endpoint = "https://${local.cp_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version = "v1.13.5"

  # Патчі: статичний IP, DNS та правильний диск
  config_patches = [
    <<-EOT
    machine:
      network:
        nameservers:
          - ${local.gateway_ip}
        interfaces:
          - interface: ens18
            dhcp: false
            addresses:
              - ${local.cp_ip}/24
            routes:
              - network: 0.0.0.0/0
                gateway: ${local.gateway_ip}
      install:
        disk: /dev/vda
        image: factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.13.5
    EOT
  ]
}

# ==========================================
# ЗАСТОСУВАННЯ КОНФІГУРАЦІЇ
# ==========================================

resource "talos_machine_configuration_apply" "cp_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_cp_01]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp_config.machine_configuration

  # IP адреса, за якою Terraform шукатиме ноду для відправки конфігурації
  #   node                        = proxmox_virtual_environment_vm.talos_cp_01.ipv4_addresses[1][0]
  # node = "192.168.0.40"
  # "Pythonic" підхід у Terraform:
  # 1. flatten() робить з масиву масивів один плоский список
  # 2. [for ip in ... if length(regexall(...))] фільтрує лише наші домашні адреси
  # 3. [0] бере перший знайдений збіг
  node = try(
    [
      for ip in flatten(proxmox_virtual_environment_vm.talos_cp_01.ipv4_addresses) : ip
      if length(regexall("^192\\.168\\.0\\.", ip)) > 0
    ][0],
    local.cp_ip
  )
}

# ==========================================
# ІНІЦІАЛІЗАЦІЯ КЛАС ТЕРА (BOOTSTRAP)
# ==========================================

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.cp_apply]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip
}

# ==========================================
# ОТРИМАННЯ KUBECONFIG ТА TALOSCONFIG
# ==========================================

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip
}


# Генеруємо правильний конфіг клієнта
data "talos_client_configuration" "talosconfig" {
  cluster_name         = "talos-k8s"
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.cp_ip]
}

# Автоматично створюємо файл kubeconfig у поточній папці
resource "local_sensitive_file" "kubeconfig" {
  depends_on = [talos_cluster_kubeconfig.kubeconfig]
  content    = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  filename   = "${path.module}/kubeconfig"
}

# Автоматично створюємо файл talosconfig у поточній папці
resource "local_sensitive_file" "talosconfig" {
  depends_on = [data.talos_client_configuration.talosconfig]
  content    = data.talos_client_configuration.talosconfig.talos_config
  filename   = "${path.module}/talosconfig"
}