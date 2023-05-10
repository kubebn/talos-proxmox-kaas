provider "proxmox" {
  pm_api_url          = var.proxmox_host
  pm_api_token_id     = var.proxmox_token_id
  pm_api_token_secret = var.proxmox_token_secret
  pm_tls_insecure     = true
  pm_debug            = true
}