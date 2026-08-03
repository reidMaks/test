terraform {
  backend "gcs" {
    bucket = "terraform-state-actual-budget-server-502619"
    prefix = "terraform/state/infra"
  }
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-alpha.5"
    }
    bitwarden-secrets = {
      source  = "bitwarden/bitwarden-secrets"
      version = "~> 1.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

data "bitwarden-secrets_secret" "proxmox_token" {
  id = "728a8819-1cd2-4f90-97dd-b49200a85353"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = data.bitwarden-secrets_secret.proxmox_token.value
  insecure  = true
}

provider "talos" {
  # Configuration options
}

resource "proxmox_hardware_mapping_pci" "intel_gpu" {
  name = "intel_gpu"

  map = [
    {
      node         = "proxmox-1"
      path         = "0000:00:02.0"
      id           = "8086:46d2"
      iommu_group  = 0
      subsystem_id = "8086:7270"
    }
  ]
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

  depends_on = [proxmox_hardware_mapping_pci.intel_gpu]

  machine = "q35"
  started = true

  boot_order = ["virtio0", "ide3", "net0"]

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
    model  = "vmxnet3"
  }

  operating_system {
    type = "l26"
  }

  dynamic "hostpci" {
    for_each = try(each.value.hostpci_mapping, null) != null ? [each.value.hostpci_mapping] : []
    content {
      device  = "hostpci0"
      mapping = hostpci.value
      pcie    = true
    }
  }

  lifecycle {
    ignore_changes = [
      network_device[0].mac_address
    ]
  }
}
