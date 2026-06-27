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

  url       = local.talos_image
  file_name = "talos-v1.13.5-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "talos" {

  for_each = local.talos_vms

  name        = each.value.name
  description = each.value.description
  tags        = ["talos", "k8s"]
  node_name   = each.value.node_name

  started = true

  agent {
    enabled = true
  }
  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    file_format  = "raw"
    size         = each.value.disk_size
  }

  cdrom {
    file_id = proxmox_download_file.talos[each.value.node_name].id
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      network_device[0].mac_address
    ]
  }
}
