variable "proxmox_endpoint" {
  type        = string
  description = "URL до Proxmox API (наприклад, https://192.168.1.10:8006/)"
}

variable "proxmox_api_token" {
  type        = string
  description = "API Token для доступу до Proxmox"
  sensitive   = true # Цей прапорець приховує токен у логах консолі
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "tenancy_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }
variable "private_key_path" { type = string }
variable "oci_region" { type = string }
variable "compartment_ocid" { type = string }

variable "region" {
  description = "The GCP Region"
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "The GCP Zone"
  type        = string
  default     = "us-east1-b"
}

variable "bitwarden_token" {
  description = "Bitwarden Secrets Manager Access Token"
  type        = string
  sensitive   = true
}