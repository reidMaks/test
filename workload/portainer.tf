# ==============================================================================
# Portainer (QNAP NAS) Configuration as Code & Authentik SSO
# ==============================================================================

resource "random_password" "portainer_akadmin_password" {
  length  = 32
  special = false
}

# Pre-create the 'akadmin' administrator account in Portainer CE so that
# when logging in via Authentik OIDC (preferred_username = "akadmin"),
# Portainer maps the session to this Administrator (role = 1) account,
# while preserving the local 'admin' account for emergency internal auth.
resource "portainer_user" "akadmin" {
  username = "akadmin"
  password = random_password.portainer_akadmin_password.result
  role     = 1
}

resource "portainer_settings" "this" {
  authentication_method = 3 # 1 = Internal, 2 = LDAP, 3 = OAuth
  snapshot_interval     = "5m"
  user_session_timeout  = "8h"

  oauth_settings {
    client_id               = "portainer"
    client_secret           = random_password.authentik_portainer_secret.result
    authorization_uri       = "https://auth.kms-lab.in.ua/application/o/authorize/"
    access_token_uri        = "https://auth.kms-lab.in.ua/application/o/token/"
    resource_uri            = "https://auth.kms-lab.in.ua/application/o/userinfo/"
    redirect_uri            = "https://portainer.home.arpa"
    logout_uri              = "https://auth.kms-lab.in.ua/application/o/portainer/end-session/"
    user_identifier         = "preferred_username"
    scopes                  = "openid email profile"
    oauth_auto_create_users = true
    sso                     = true
    hide_internal_auth      = false
    auth_style              = 0
  }

  depends_on = [portainer_user.akadmin]
}
