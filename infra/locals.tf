locals {
  pve_nodes = ["master", "proxmox-1", "proxmox-2"]


  gateway_ip = "192.168.0.1"

  talos_vms = {
    "cp_01" = {
      name         = "talos-cp-01"
      description  = "Kubernetes Control Plane 01 (Talos)"
      node_name    = "master"
      cores        = 2
      memory       = 2048
      disk_size    = 10
      ip           = "192.168.0.40"
      machine_type = "controlplane"
    }
    "worker_01" = {
      name         = "talos-worker-01"
      description  = "Kubernetes worker 01 (Talos)"
      node_name    = "proxmox-1"
      cores        = 3
      memory       = 4096
      disk_size    = 30
      ip           = "192.168.0.41"
      machine_type = "worker"
    }
    "worker_02" = {
      name         = "talos-worker-02"
      description  = "Kubernetes worker 02 (Talos)"
      node_name    = "proxmox-2"
      cores        = 6
      memory       = 8192
      disk_size    = 60
      ip           = "192.168.0.42"
      machine_type = "worker"
    }
  }

  cp_ip = [for v in local.talos_vms : v.ip if v.machine_type == "controlplane"][0]
}
