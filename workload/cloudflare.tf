data "cloudflare_zone" "main" {
  name = "kms-lab.in.ua"
}

locals {
  cf_tunnel_cname = "5e95d7b5-b74d-4a93-bd8c-123f8980f3ed.cfargotunnel.com"
}

# -----------------------------------------------------
# A Records (Unproxied)
# -----------------------------------------------------

# Внутрішній роутинг для VPN клієнтів (резолв будь-якого піддомену на IP WG Hub)
resource "cloudflare_record" "wildcard_internal" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*"
  content = "10.9.0.1"
  type    = "A"
  proxied = false
  comment = "wg tunnel internal routing"
}

# Публічний IP вашої OCI ноди для WireGuard VPN
resource "cloudflare_record" "vpn" {
  zone_id = data.cloudflare_zone.main.id
  name    = "vpn"
  content = "152.67.85.188"
  type    = "A"
  proxied = false
  comment = "OCI WG Hub public IP"
}

# -----------------------------------------------------
# CNAME Records (Proxied via Cloudflare Tunnel)
# -----------------------------------------------------

resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "kms-lab.in.ua"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "lubelogger" {
  zone_id = data.cloudflare_zone.main.id
  name    = "lubelogger"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "tandoor" {
  zone_id = data.cloudflare_zone.main.id
  name    = "tandoor"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "wishlist" {
  zone_id = data.cloudflare_zone.main.id
  name    = "wishlist"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
}
