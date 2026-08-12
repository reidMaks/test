locals {
  pve_nodes = ["master", "proxmox-1", "proxmox-2"]

  talos_version          = "v1.13.5"
  talos_schematic_id     = talos_image_factory_schematic.this.id
  talos_oci_schematic_id = "b2c39cfaec0508c46e30a90dc10041c3cd6942bed31654e43933f8c0e6b0e428"

  talos_image     = "https://factory.talos.dev/image/${local.talos_schematic_id}/${local.talos_version}/metal-amd64.iso"
  talos_gcp_image = "https://factory.talos.dev/image/${local.talos_schematic_id}/${local.talos_version}/gcp-amd64.raw.tar.gz"
  talos_oci_image = "https://factory.talos.dev/image/${local.talos_oci_schematic_id}/${local.talos_version}/oracle-arm64.raw.xz"
  talos_installer = "factory.talos.dev/metal-installer/${local.talos_schematic_id}:${local.talos_version}"

  gateway_ip = "192.168.0.1"

  talos_vms = {
    "cp_01" = {
      name         = "talos-cp-01"
      description  = "Kubernetes Control Plane 01 (Talos)"
      node_name    = "master"
      cores        = 3
      memory       = 4096
      disk_size    = 10
      ip           = "192.168.0.40"
      machine_type = "controlplane"
    }
    "worker_01" = {
      name            = "talos-worker-01"
      description     = "Kubernetes worker 01 (Talos)"
      node_name       = "proxmox-1"
      cores           = 4
      memory          = 12288
      disk_size       = 90
      ip              = "192.168.0.41"
      machine_type    = "worker"
      hostpci_mapping = "intel_gpu"
    }
    "worker_02" = {
      name         = "talos-worker-02"
      description  = "Kubernetes worker 02 (Talos)"
      node_name    = "proxmox-2"
      cores        = 6
      memory       = 12288
      disk_size    = 90
      ip           = "192.168.0.42"
      machine_type = "worker"
    }
  }

  oci_vms = {
    "talos_oci" = {
      display_name  = "talos-cp-oci"
      ocpus         = 2
      memory_in_gbs = 12
    }
    "talos_oci_2" = {
      display_name  = "talos-cp-oci-2"
      ocpus         = 2
      memory_in_gbs = 12
    }
  }

  cp_ip = [for v in local.talos_vms : v.ip if v.machine_type == "controlplane"][0]
}
