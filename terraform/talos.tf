resource "talos_machine_secrets" "secrets" {}

data "talos_machine_configuration" "mc_1" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.secrets.machine_secrets
  kubernetes_version = var.k8s_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches = [
    templatefile("${path.module}/templates/controlplane.yaml.tpl",
      merge(var.kubernetes, {
        hostname         = "master-0"
        ipv4_local       = "${cidrhost(var.vpc_main_cidr, var.first_ip)}"
        identity         = "${file(var.private_key_file_path)}"
        identitypub      = "${file(var.public_key_file_path)}"
        knownhosts       = var.known_hosts
        px_region        = var.region
        px_node          = var.target_node_name
        storageclass     = var.proxmox_storage2
        storageclass-xfs = var.proxmox_storage1
        clusters = yamlencode({
          clusters = [
            {
              token_id     = var.proxmox_token_id
              token_secret = var.proxmox_token_secret
              url          = var.proxmox_host
              region       = var.region
            },
          ]
        })
        pxcreds = yamlencode({
          clusters = {
            cluster-1 = {
              api_token_id     = var.proxmox_token_id
              api_token_secret = var.proxmox_token_secret
              api_url          = var.proxmox_host
              pool             = var.pool
            }
          }
        })
      })
    )
  ]
}

data "talos_machine_configuration" "mc_2" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.secrets.machine_secrets
  kubernetes_version = var.k8s_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches = [
    templatefile("${path.module}/templates/controlplane.yaml.tpl",
      merge(var.kubernetes, {
        hostname         = "master-1"
        ipv4_local       = "${cidrhost(var.vpc_main_cidr, var.first_ip + 1)}"
        identity         = "${file(var.private_key_file_path)}"
        identitypub      = "${file(var.public_key_file_path)}"
        knownhosts       = var.known_hosts
        px_region        = var.region
        px_node          = var.target_node_name
        storageclass     = var.proxmox_storage2
        storageclass-xfs = var.proxmox_storage1
        clusters = yamlencode({
          clusters = [
            {
              token_id     = var.proxmox_token_id
              token_secret = var.proxmox_token_secret
              url          = var.proxmox_host
              region       = var.region
            },
          ]
        })
        pxcreds = yamlencode({
          clusters = {
            cluster-1 = {
              api_token_id     = var.proxmox_token_id
              api_token_secret = var.proxmox_token_secret
              api_url          = var.proxmox_host
              pool             = var.pool
            }
          }
        })
      })
    )
  ]
}

data "talos_machine_configuration" "mc_3" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.secrets.machine_secrets
  kubernetes_version = var.k8s_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches = [
    templatefile("${path.module}/templates/controlplane.yaml.tpl",
      merge(var.kubernetes, {
        hostname         = "master-2"
        ipv4_local       = "${cidrhost(var.vpc_main_cidr, var.first_ip + 2)}"
        identity         = "${file(var.private_key_file_path)}"
        identitypub      = "${file(var.public_key_file_path)}"
        knownhosts       = var.known_hosts
        px_region        = var.region
        px_node          = var.target_node_name
        storageclass     = var.proxmox_storage2
        storageclass-xfs = var.proxmox_storage1
        clusters = yamlencode({
          clusters = [
            {
              token_id     = var.proxmox_token_id
              token_secret = var.proxmox_token_secret
              url          = var.proxmox_host
              region       = var.region
            },
          ]
        })
        pxcreds = yamlencode({
          clusters = {
            cluster-1 = {
              api_token_id     = var.proxmox_token_id
              api_token_secret = var.proxmox_token_secret
              api_url          = var.proxmox_host
              pool             = var.pool
            }
          }
        })
      })
    )
  ]
}

data "talos_client_configuration" "cc" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.secrets.client_configuration
  nodes                = [var.kubernetes["ipv4_vip"], "${cidrhost(var.vpc_main_cidr, var.first_ip)}"]
  endpoints            = [var.kubernetes["ipv4_vip"], "${cidrhost(var.vpc_main_cidr, var.first_ip)}"]
}


resource "talos_machine_configuration_apply" "mc_apply_1" {
  depends_on = [
    proxmox_vm_qemu.controlplanes
  ]
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.mc_1.machine_configuration
  node                        = cidrhost(var.vpc_main_cidr, var.first_ip)
}

resource "talos_machine_configuration_apply" "mc_apply_2" {
  depends_on = [
    proxmox_vm_qemu.controlplanes
  ]
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.mc_2.machine_configuration
  node                        = cidrhost(var.vpc_main_cidr, var.first_ip + 1)
}

resource "talos_machine_configuration_apply" "mc_apply_3" {
  depends_on = [
    proxmox_vm_qemu.controlplanes
  ]
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.mc_3.machine_configuration
  node                        = cidrhost(var.vpc_main_cidr, var.first_ip + 2)
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [
    talos_machine_configuration_apply.mc_apply_1
  ]
  node                 = cidrhost(var.vpc_main_cidr, var.first_ip)
  client_configuration = talos_machine_secrets.secrets.client_configuration
}

data "talos_machine_configuration" "worker_1" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.secrets.machine_secrets
  kubernetes_version = var.k8s_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches = [
    templatefile("${path.module}/templates/worker.yaml.tpl",
      merge(var.kubernetes, {
        hostname   = "worker-0"
        ipv4_local = "${cidrhost(var.vpc_main_cidr, var.worker_first_ip)}"
        px_region  = var.region
        px_node    = var.target_node_name
      })
    )
  ]
}

data "talos_machine_configuration" "worker_2" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.secrets.machine_secrets
  kubernetes_version = var.k8s_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches = [
    templatefile("${path.module}/templates/worker.yaml.tpl",
      merge(var.kubernetes, {
        hostname   = "worker-1"
        ipv4_local = "${cidrhost(var.vpc_main_cidr, var.worker_first_ip + 1)}"
        px_region  = var.region
        px_node    = var.target_node_name
      })
    )
  ]
}

data "talos_machine_configuration" "worker_3" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.secrets.machine_secrets
  kubernetes_version = var.k8s_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches = [
    templatefile("${path.module}/templates/worker.yaml.tpl",
      merge(var.kubernetes, {
        hostname   = "worker-2"
        ipv4_local = "${cidrhost(var.vpc_main_cidr, var.worker_first_ip + 2)}"
        px_region  = var.region
        px_node    = var.target_node_name
      })
    )
  ]
}

resource "talos_machine_configuration_apply" "worker_apply_1" {
  depends_on = [
    proxmox_vm_qemu.workers
  ]
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker_1.machine_configuration
  node                        = cidrhost(var.vpc_main_cidr, var.worker_first_ip)
}

resource "talos_machine_configuration_apply" "worker_apply_2" {
  depends_on = [
    proxmox_vm_qemu.workers
  ]
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker_2.machine_configuration
  node                        = cidrhost(var.vpc_main_cidr, var.worker_first_ip + 1)
}

resource "talos_machine_configuration_apply" "worker_apply_3" {
  depends_on = [
    proxmox_vm_qemu.workers
  ]
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker_3.machine_configuration
  node                        = cidrhost(var.vpc_main_cidr, var.worker_first_ip + 2)
}