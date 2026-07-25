variable "proxmox_endpoint" {
  type        = string
  description = "URL до Proxmox API (наприклад, https://192.168.1.10:8006/)"
}



variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "tenancy_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }

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
