provider "bitwarden-secrets" {
  api_url         = "https://api.bitwarden.eu"
  identity_url    = "https://identity.bitwarden.eu"
  access_token    = var.bitwarden_token
  organization_id = "dd4d4a61-6bc9-4fce-9f6d-b41b0077db8c"
}
