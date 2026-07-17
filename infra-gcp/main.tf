terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    bitwarden-secrets = {
      source  = "bitwarden/bitwarden-secrets"
      version = "~> 1.0"
    }
  }
}

provider "google" {
  credentials = file("../tmp/gcp-creds.json")
  project     = var.project_id
  region      = var.region
  zone        = var.zone
}

data "bitwarden-secrets_secret" "monobank_token" {
  id = "3f16903e-c45e-47b6-9716-b478016cd900"
}

resource "google_compute_address" "static_ip" {
  name = "actual-budget-ipv4-useast1"
}

resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

resource "google_compute_instance" "actual_budget_vm" {
  name         = "actual-budget-server"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup.sh", {
      docker_compose_b64 = base64encode(file("../workload/actualbudget/docker-compose.yml")),
      caddyfile_b64      = base64encode(file("../workload/actualbudget/Caddyfile")),
      addon_py_b64       = base64encode(file("../workload/actualbudget/addon.py")),
      monobank_token     = data.bitwarden-secrets_secret.monobank_token.value
    })
  }
}

output "server_ip" {
  description = "The public IP address of your new server"
  value       = google_compute_address.static_ip.address
}
