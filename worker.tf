# ==========================================
# ГЕНЕРАЦІЯ КОНФІГУРАЦІЇ ДЛЯ WORKER 01
# ==========================================

data "talos_machine_configuration" "worker_config" {
  cluster_name     = "talos-k8s"
  cluster_endpoint = "https://${local.cp_ip}:6443" 
  

  machine_type     = "worker"                      
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version    = "v1.13.5"

  config_patches = [
    <<-EOT
    machine:
      network:
        nameservers:
          - 8.8.8.8
          - 1.1.1.1
          - ${local.gateway_ip}
        interfaces:
          - interface: ens18
            dhcp: false
            addresses:
              - ${local.worker01_ip}/24 # Використовуємо IP воркера
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
# ЗАСТОСУВАННЯ КОНФІГУРАЦІЇ ДЛЯ WORKER 01
# ==========================================

resource "talos_machine_configuration_apply" "worker_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_worker_01]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker_config.machine_configuration
  
  node = length(flatten(proxmox_virtual_environment_vm.talos_worker_01.ipv4_addresses)) > 0 ? [
    for ip in flatten(proxmox_virtual_environment_vm.talos_worker_01.ipv4_addresses) : ip 
    if length(regexall("^192\\.168\\.0\\.", ip)) > 0
  ][0] : local.worker01_ip
}