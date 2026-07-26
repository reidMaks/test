# ==========================================
# ГЕНЕРАЦІЯ КОНФІГУРАЦІЇ ДЛЯ CONTROL PLANE
# ==========================================

data "talos_machine_configuration" "config" {

  for_each = local.talos_vms

  cluster_name     = "talos-k8s"
  cluster_endpoint = "https://${local.cp_ip}:6443"
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version = local.talos_version

  # Патчі: статичний IP, DNS та правильний диск
  config_patches = concat(
    [
      <<-EOT
      machine:
        nodeLabels:
          topology.kubernetes.io/zone: "home"
        network:
          kubespan:
            enabled: true
          nameservers:
            - 8.8.8.8
            - 1.1.1.1
            - ${local.gateway_ip}
          interfaces:
            - interface: ens18
              dhcp: false
              addresses:
                - ${each.value.ip}/24
              routes:
                - network: 0.0.0.0/0
                  gateway: ${local.gateway_ip}
        kubelet:
          extraMounts:
            - destination: /var/lib/longhorn
              type: bind
              source: /var/lib/longhorn
              options:
                - bind
                - rshared
                - rw
        kernel:
          modules:
            - name: nbd
            - name: iscsi_tcp
            - name: configfs
        install:
          disk: /dev/vda
          image: ${local.talos_installer}
      EOT
    ],
    each.value.machine_type == "controlplane" ? [
      <<-EOT
      cluster:
        etcd:
          extraArgs:
            heartbeat-interval: "500"
            election-timeout: "5000"
      EOT
    ] : []
  )
}




resource "talos_machine_configuration_apply" "apply" {

  for_each = local.talos_vms

  depends_on                  = [proxmox_virtual_environment_vm.talos]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.config[each.key].machine_configuration

  # IP адреса, за якою Terraform шукатиме ноду для відправки конфігурації
  #   node                        = proxmox_virtual_environment_vm.talos_cp_01.ipv4_addresses[1][0]
  # node = "192.168.0.40"
  # "Pythonic" підхід у Terraform:
  # 1. flatten() робить з масиву масивів один плоский список
  # 2. [for ip in ... if length(regexall(...))] фільтрує лише наші домашні адреси
  # 3. [0] бере перший знайдений збіг
  node = try(
    [
      for ip in flatten(proxmox_virtual_environment_vm.talos[each.key].ipv4_addresses) : ip
      if length(regexall("^192\\.168\\.0\\.", ip)) > 0
    ][0],
    each.value.ip
  )
}

# ==========================================
# ІНІЦІАЛІЗАЦІЯ КЛАСТЕРА (BOOTSTRAP)
# ==========================================

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.apply]
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

# ==========================================
# GCP WITNESS NODE
# ==========================================



# ==========================================
# OCI WITNESS NODE
# ==========================================

data "talos_machine_configuration" "oci" {
  cluster_name     = "talos-k8s"
  cluster_endpoint = "https://${local.cp_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version = local.talos_version

  config_patches = [
    <<-EOT
    machine:
      nodeLabels:
        node-role.kubernetes.io/control-plane: ""
        topology.kubernetes.io/zone: "oci"
      certSANs:
        - ${oci_core_instance.talos_oci.public_ip}
      network:
        kubespan:
          enabled: true
        # Хак для обходу NAT: додаємо публічний IP до loopback (lo).
        # Talos автоматично розпізнає цей IP і передасть його KubeSpan,
        # що дозволить хмарним нодам з'єднуватись безпосередньо.
        interfaces:
          - interface: lo
            addresses:
              - ${oci_core_instance.talos_oci.public_ip}/32
    cluster:
      allowSchedulingOnControlPlanes: true
      etcd:
        extraArgs:
          heartbeat-interval: "500"
          election-timeout: "5000"
    EOT
  ]
}

resource "talos_machine_configuration_apply" "oci" {
  depends_on                  = [oci_core_instance.talos_oci]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.oci.machine_configuration
  node                        = oci_core_instance.talos_oci.public_ip
}

# ==========================================
# OCI NODE 2
# ==========================================

data "talos_machine_configuration" "oci_2" {
  cluster_name     = "talos-k8s"
  cluster_endpoint = "https://${local.cp_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version = local.talos_version

  config_patches = [
    <<-EOT
    machine:
      nodeLabels:
        node-role.kubernetes.io/control-plane: ""
        topology.kubernetes.io/zone: "oci"
      certSANs:
        - ${oci_core_instance.talos_oci_2.public_ip}
      network:
        kubespan:
          enabled: true
        interfaces:
          - interface: lo
            addresses:
              - ${oci_core_instance.talos_oci_2.public_ip}/32
    cluster:
      allowSchedulingOnControlPlanes: true
      etcd:
        extraArgs:
          heartbeat-interval: "500"
          election-timeout: "5000"
    EOT
  ]
}

resource "talos_machine_configuration_apply" "oci_2" {
  depends_on                  = [oci_core_instance.talos_oci_2]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.oci_2.machine_configuration
  node                        = oci_core_instance.talos_oci_2.public_ip
}
