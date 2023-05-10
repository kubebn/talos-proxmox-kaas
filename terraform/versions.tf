# TF setup

terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 2.9.14"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.2.0"
    }
  }
}