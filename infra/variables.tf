variable "proxmox_endpoint" {
  type        = string
  description = "URL до Proxmox API (наприклад, https://192.168.1.10:8006/)"
}

variable "proxmox_api_token" {
  type        = string
  description = "API Token для доступу до Proxmox"
  sensitive   = true # Цей прапорець приховує токен у логах консолі
}