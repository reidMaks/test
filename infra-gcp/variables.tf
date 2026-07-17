variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

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
