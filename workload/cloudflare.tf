data "cloudflare_zone" "main" {
  name = "kms-lab.in.ua"
}

data "cloudflare_zone" "apn" {
  name = "apn.in.ua"
}

locals {
  cf_account_id   = "62d8fde3db38cd68e002236995dfea97"
  cf_tunnel_id    = "5e95d7b5-b74d-4a93-bd8c-123f8980f3ed"
  cf_tunnel_cname = "${local.cf_tunnel_id}.cfargotunnel.com"
  traefik_origin  = "http://traefik.traefik-system.svc.cluster.local:80"
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

# Публічний IP OCI ноди для власного сервера RustDesk (hbbs/hbbr)
resource "cloudflare_record" "rustdesk" {
  zone_id = data.cloudflare_zone.main.id
  name    = "rustdesk"
  content = "152.67.85.188"
  type    = "A"
  proxied = false
  comment = "OCI RustDesk Server (hbbs/hbbr) public IP"
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

resource "cloudflare_record" "plan" {
  zone_id = data.cloudflare_zone.main.id
  name    = "plan"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "plan_api" {
  zone_id = data.cloudflare_zone.main.id
  name    = "plan-api"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
}

# -----------------------------------------------------
# APN Production Domain (apn.in.ua) — DNS, Tunnel & Free WAF/RateLimit
# -----------------------------------------------------

resource "cloudflare_record" "apn_root" {
  zone_id = data.cloudflare_zone.apn.id
  name    = "apn.in.ua"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
  comment = "APN Production root domain via Cloudflare Tunnel"
}

resource "cloudflare_record" "apn_www" {
  zone_id = data.cloudflare_zone.apn.id
  name    = "www"
  content = local.cf_tunnel_cname
  type    = "CNAME"
  proxied = true
  comment = "APN Production www subdomain via Cloudflare Tunnel"
}

# Декларативна конфігурація маршрутів Cloudflare Tunnel (Zero Trust Free)
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = local.cf_account_id
  tunnel_id  = local.cf_tunnel_id

  config {
    warp_routing {
      enabled = false
    }

    ingress_rule {
      hostname = "tandoor.kms-lab.in.ua"
      service  = local.traefik_origin
    }

    ingress_rule {
      hostname = "plan.kms-lab.in.ua"
      service  = local.traefik_origin
    }

    ingress_rule {
      hostname = "wishlist.kms-lab.in.ua"
      service  = local.traefik_origin
    }

    ingress_rule {
      hostname = "lubelogger.kms-lab.in.ua"
      service  = local.traefik_origin
    }

    ingress_rule {
      hostname = "plan-api.kms-lab.in.ua"
      service  = local.traefik_origin
    }

    ingress_rule {
      hostname = "apn.in.ua"
      service  = local.traefik_origin
    }

    ingress_rule {
      hostname = "www.apn.in.ua"
      service  = local.traefik_origin
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Cloudflare Free WAF Custom Rule (до 5 безкоштовних правил на зону):
# Пропуск (skip) вебхуків Monobank Checkout повз Rate Limit та Managed WAF
resource "cloudflare_ruleset" "apn_waf_custom" {
  zone_id     = data.cloudflare_zone.apn.id
  name        = "APN Custom WAF Rules"
  description = "Free-tier WAF custom rules for apn.in.ua (Monobank webhook bypass)"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    description = "Bypass WAF & Rate Limiting for Monobank Checkout webhooks"
    expression  = "(http.request.uri.query contains \"wc-api=wc_monobank\")"
    action      = "skip"
    enabled     = true

    action_parameters {
      phases = [
        "http_ratelimit",
        "http_request_firewall_managed"
      ]
    }

    logging {
      enabled = true
    }
  }
}

# Cloudflare Free Rate Limiting Rule (1 безкоштовне правило на зону):
# Захист /wp-login.php та /wp-json/ від перебору паролів і флуду
resource "cloudflare_ruleset" "apn_rate_limit" {
  zone_id     = data.cloudflare_zone.apn.id
  name        = "APN Rate Limiting"
  description = "Free-tier Rate Limit for wp-login.php and wp-json"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules {
    description = "Rate limit /wp-login.php and /wp-json/ (Free tier: 20 req / 10s per IP)"
    expression  = "(http.request.uri.path eq \"/wp-login.php\") or (starts_with(http.request.uri.path, \"/wp-json/\"))"
    action      = "block"
    enabled     = true

    ratelimit {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 10
      requests_per_period = 20
      mitigation_timeout  = 10
    }
  }
}
