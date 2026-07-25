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
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
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

data "bitwarden-secrets_secret" "gcp_creds" {
  id = "35f051fc-df4b-4627-8472-b492007d6f77"
}

provider "google" {
  credentials = data.bitwarden-secrets_secret.gcp_creds.value
  project     = var.project_id
  region      = var.region
  zone        = var.zone
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

  lifecycle {
    ignore_changes = [
      network_device[0].mac_address
    ]
  }
}

resource "null_resource" "download_talos" {
  provisioner "local-exec" {
    command = "wget -qO gcp-amd64.raw.tar.gz ${local.talos_gcp_image}"
  }
}

resource "google_storage_bucket" "talos_bucket" {
  name          = "${var.project_id}-talos"
  location      = "US" # US multi-region is covered by Free Tier
  force_destroy = true
}

resource "google_storage_bucket_object" "talos_image" {
  name       = "gcp-amd64.raw.tar.gz"
  bucket     = google_storage_bucket.talos_bucket.name
  source     = "gcp-amd64.raw.tar.gz"
  depends_on = [null_resource.download_talos]

  lifecycle {
    ignore_changes = [detect_md5hash]
  }
}

resource "google_compute_image" "talos" {
  name = "talos-${replace(local.talos_version, ".", "-")}-${substr(local.talos_schematic_id, 0, 7)}"
  raw_disk {
    source = "https://storage.googleapis.com/${google_storage_bucket.talos_bucket.name}/${google_storage_bucket_object.talos_image.name}"
  }
}

resource "google_compute_firewall" "allow_talos" {
  name    = "allow-talos"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["50000", "6443"]
  }

  allow {
    protocol = "udp"
    ports    = ["51820", "51821"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["talos"]
}

resource "google_compute_instance" "gcp_cp" {
  name         = "talos-cp-gcp"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["talos", "k8s"]

  boot_disk {
    initialize_params {
      image = google_compute_image.talos.self_link
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      # Ephemeral IP
    }
  }
}
