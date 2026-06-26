terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-alpha.5"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

provider "talos" {
  # Configuration options
}

resource "talos_machine_secrets" "this" {}



# download talos iso

resource "proxmox_download_file" "talos" {
  for_each     = toset(local.pve_nodes)
  content_type = "iso"
  datastore_id = "local"
  node_name    = each.value

  url       = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.5/nocloud-amd64.iso"
  file_name = "talos-v1.13.5-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "talos_cp_01" {
  name        = "talos-cp-01"
  description = "Kubernetes Control Plane 01 (Talos)"
  tags        = ["talos", "k8s"]
  node_name   = "master"

  started = true

  agent {
    enabled = true
  }
  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    file_format  = "raw"
    size         = 10
  }

  cdrom {
    file_id = proxmox_download_file.talos["master"].id
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"
  }
}



resource "proxmox_virtual_environment_vm" "talos_worker_01" {
  name        = "talos-worker-01"
  description = "Kubernetes worker 01 (Talos)"
  tags        = ["talos", "k8s"]
  node_name   = "proxmox-1"

  started = true

  agent {
    enabled = true
  }
  cpu {
    cores = 3
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    file_format  = "raw"
    size         = 30
  }

  cdrom {
    file_id = proxmox_download_file.talos["proxmox-1"].id
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"
  }
}