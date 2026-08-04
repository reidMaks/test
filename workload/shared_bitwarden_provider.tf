provider "bitwarden-secrets" {
  api_url      = "https://api.bitwarden.eu"
  identity_url = "https://identity.bitwarden.eu"

  organization_id = "dd4d4a61-6bc9-4fce-9f6d-b41b0077db8c"
}

data "bitwarden-secrets_secret" "open_router_api_key" {
  id = "d16fb37b-484f-435f-abb1-b49700805557"
}
