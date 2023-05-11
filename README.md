Kubernetes As a Service (KAAS) in Proxmox
=================

### Introduction

The purpose of this lab to demonstrate capabilities of ***Talos Linux, Sidero (CAPI), FluxCD & Proxmox Operator***, and how they can be used to provision k8s clusters in a true GitOps way.

---
### Built With:

* [Talos Linux](https://talos.dev)
* [Sidero & CAPI](https://sidero.dev)
* [Talos Terraform Provider](https://registry.terraform.io/providers/siderolabs/talos/latest)
* [Proxmox Terraform Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest)
* [Packer](https://www.packer.io/)
* [FluxCD](https://fluxcd.io/flux/)

### k8s in-cluster tools:

* [Proxmox operator](https://github.com/CRASH-Tech/proxmox-operator)
* [Proxmox CCM](https://github.com/sergelogvinov/proxmox-cloud-controller-manager)
* [Talos CCM](https://github.com/sergelogvinov/talos-cloud-controller-manager)
* [Proxmox CSI](https://github.com/sergelogvinov/proxmox-csi-plugin)
* [Cilium](https://cilium.io/)

Repository structure
=================

```bash
├── kubernetes # App manifests synced via FluxCD & FluxCD configurations
├── manifests # App (system-components) applied via Talos Linux controlplane templates
├── packer # Builds Talos disk on top of Arch Linux for cloud-init functionalities
├── terraform # Proxmox & Talos terraform providers to provision Talos Management cluster
    ├── templates # Management Cluster configurations
    ├── output.tf # Terraform output
    ├── master-nodes.tf # Proxmox master nodes - Management cluster
    ├── worker-nodes.tf # Proxmox worker nodes - Management cluster
    ├── k8s.tf # Fetches Talosconfig & Kubeconfig
    ├── variables.tf # Terraform variables
    ├── terraform.tfvars # Variables to be set here
    ├── talos.tf # Talos provider generates secrets, encodes configuration templates, and applies them to the machines
    └── versions.tf # Terraform providers
```

Overview
=================

The lab is divided into four stages:

* Setting up the Proxmox nodes and preparing the cluster, with terraform variables set. This stage is not automated.
* Building and templating the Talos image using packer. This process can also be done manually, with instructions provided in the documentation.
* Setting the terraform.tfvars and running terraform to create ***the Management k8s cluster***. The cluster includes:
    * 3 Masters & 3 workers
    * [Cilium in strict, tunnel disabled mode](manifests/talos/cilium.yaml) automatically synced with the k8s API through the `api.cluster.local` domain.
    * Talos & Proxmox CCM
    * Metrics-Server
    * CordeDNS-local
    * [MetalLB in L2 mode](terraform/templates/controlplane.yaml.tpl)
    * Prometheus CRD's
    * Bootstrapped and installed FluxCD, which syncs the following apps:
        * cert-manager
        * dhcp server
        * proxmox operator and CSI plugin
        * Sidero & CAPI
        * Additionally, it creates [cluster-0](kubernetes/apps/clusters/cluster-0/) demo cluster
* Sidero cluster bootstrap

Table of contents
=================

<!--ts-->
- [Kubernetes As a Service (KAAS) in Proxmox](#kubernetes-as-a-service--kaas--in-proxmox)
    + [Introduction](#introduction)
    + [Built With:](#built-with-)
    + [k8s in-cluster tools:](#k8s-in-cluster-tools-)
- [Repository structure](#repository-structure)
- [Overview](#overview)
- [Prerequisites](#prerequisites)
  * [CLI](#cli)
  * [Proxmox Node & Cluster configuration](#proxmox-node---cluster-configuration)
  * [Cilium CNI configuration](#cilium-cni-configuration)
  * [Pull Through Image Cache](#pull-through-image-cache)
- [Installation](#installation)
    + [DHCP Disabled](#dhcp-disabled)
  * [Variables](#variables)
  * [Packer](#packer)
    + [Manual method](#manual-method)
  * [Terraform](#terraform)
    + [terraform plan](#terraform-plan)
    + [terraform apply](#terraform-apply)
    + [terraform output for talosconfig & kubeconfig can be checked if needed](#terraform-output-for-talosconfig---kubeconfig-can-be-checked-if-needed)
    + [CSI testing](#csi-testing)
  * [Sidero Bootstrap](#sidero-bootstrap)
    + [Scaling](#scaling)
    + [New clusters](#new-clusters)
  * [Teraform destroy](#teraform-destroy)
- [References](#references)
    + [terraform gitignore template](#terraform-gitignore-template)

<!--te-->

<p align="right">(<a href="#introduction">back to top</a>)</p>

Prerequisites
============

## CLI
You will need these CLI tools installed on your workstation

* talosctl CLI:
 ```bash
 curl -sL https://talos.dev/install | sh
 ```
 * [kubectl](https://kubernetes.io/docs/tasks/tools/)
 * [clusterctl](https://cluster-api.sigs.k8s.io/user/quick-start.html#install-clusterctl)
 * [packer](https://developer.hashicorp.com/packer/downloads)
 * [terraform](https://developer.hashicorp.com/terraform/downloads?product_intent=terraform)
 * [helm](https://helm.sh/docs/intro/install/)

 ## Proxmox Node & Cluster configuration

This lab consists of a single Proxmox node with [Masquerading (NAT) with iptables configured](https://pve.proxmox.com/wiki/Network_Configuration)

```bash
auto lo
iface lo inet loopback

auto enp42s0
iface enp42s0 inet static
        address 192.168.1.100/24
        gateway 192.168.1.1

iface wlo1 inet manual

auto vmbr0
iface vmbr0 inet static
        address 10.1.1.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
        post-up   iptables -t nat -A POSTROUTING -s '10.1.1.0/24' -o enp42s0 -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s '10.1.1.0/24' -o enp42s0 -j MASQUERADE
        # wireguard vpn virtual machine config
        post-up   iptables -t nat -A PREROUTING -p udp -d 192.168.1.100 --dport 52890 -i enp42s0 -j DNAT --to-destination 10.1.1.2:52890
        post-down iptables -t nat -A PREROUTING -p udp -d 192.168.1.100 --dport 52890 -i enp42s0 -j DNAT --to-destination 10.1.1.2:52890
```

The lab infrastructure is provisioned using a flat 10.1.1.0/24 network. Make sure to change the variables according to your networking setup. In addition, ensure that the Proxmox storage names in the [terraform.tfvars](terraform/terraform.tfvars) file are correct.

Although there is only one Proxmox node, a cluster (cluster-1) was initialized using the UI for testing purposes of [Proxmox CCM](https://github.com/sergelogvinov/proxmox-cloud-controller-manager) & [Talos CCM](https://github.com/sergelogvinov/talos-cloud-controller-manager) & [Proxmox CSI](https://github.com/sergelogvinov/proxmox-csi-plugin).

To build the Talos image with cloud-init functionalities, download the Arch Linux image from [here](https://archlinux.org/download/), use the following command on the Proxmox machine:

```bash
wget -nc -q --show-progress -O "/var/lib/vz/template/iso/archlinux-2023.04.01-x86_64.iso" "http://archlinux.uk.mirror.allworldit.com/archlinux/iso/2023.04.01/archlinux-2023.04.01-x86_64.iso"
```

You will need to use that image in "iso_file" [packer here](packer/proxmox.pkr.hcl)

<p align="right">(<a href="#introduction">back to top</a>)</p>

## Cilium CNI configuration

The following Helm chart template was used to generate a [plain yaml manifest](manifests/talos/cilium.yaml), which is then applied in the  [Talos control plane template](terraform/templates/controlplane.yaml.tpl):

```bash
helm template cilium \
    cilium/cilium \
    --version 1.13.2 \
    --namespace cilium \
    --set ipam.mode=kubernetes \
    --set tunnel=disabled \
    --set bpf.masquerade=true \
    --set endpointRoutes.enabled=true \
    --set kubeProxyReplacement=strict \
    --set autoDirectNodeRoutes=true \
    --set localRedirectPolicy=true \
    --set operator.rollOutPods=true \
    --set rollOutCiliumPods=true \
    --set ipv4NativeRoutingCIDR="10.244.0.0/16" \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set=cgroup.autoMount.enabled=false \
    --set=cgroup.hostRoot=/sys/fs/cgroup \
    --set=k8sServiceHost="api.cluster.local" \
    --set=k8sServicePort="6443"
```
Talos `clusterDNS` & `ExtraHostEntries` were added to the controlplane & worker configurations:

```bash
clusterDNS:
- 169.254.2.53
- ${cidrhost(split(",",serviceSubnets)[0], 10)}

---

- interface: dummy0
addresses:
    - 169.254.2.53/32
extraHostEntries:
- ip: 127.0.0.1
aliases:
    - ${apiDomain} 
```
By using the configuration from the [coredns-local](manifests/talos/coredns-local.yaml) manifest, we can avoid to create separate cilium manifests for each k8s cluster. This is because each cluster has a different k8s cluster API endpoint. To accomplish this, the `api.cluster.local` domain is added to the coredns configuration, allowing us to apply the same cilium CNI manifest to multiple clusters.

<p align="right">(<a href="#introduction">back to top</a>)</p>

## Pull Through Image Cache

In order to speed up the provisioning of the clusters and their components, we use [Talos Pull Through Image Cache](https://www.talos.dev/v1.4/talos-guides/configuration/pull-through-cache/) & Harbor registry.  Although this lab does not include the creation and configuration of a Docker registry, automation for Proxmox may be added in the future. If you do not wish to use the Pull image cache, you can delete the following lines in [controlplane](terraform/templates/controlplane.yaml.tpl) & [workers](terraform/templates/worker.yaml.tpl):

```bash
  registries:
    mirrors:
      docker.io:
        endpoints:
          - http://${registry-endpoint}/v2/proxy-docker.io
        overridePath: true
      ghcr.io:
        endpoints:
          - http://${registry-endpoint}/v2/proxy-ghcr.io
        overridePath: true
      gcr.io:
        endpoints:
          - http://${registry-endpoint}/v2/proxy-gcr.io
        overridePath: true
      registry.k8s.io:
        endpoints:
          - http://${registry-endpoint}/v2/proxy-registry.k8s.io
        overridePath: true
      quay.io:
        endpoints:
          - http://${registry-endpoint}/v2/proxy-quay.io
        overridePath: true
```

<p align="right">(<a href="#introduction">back to top</a>)</p>

Installation
============
### DHCP Disabled

**To facilitate the testing of this lab, we need to disable the DHCP service in the infrastructure network; in my configuration vm network is 10.1.1.0/24. This is necessary because a DHCP server will be running inside the Management k8s cluster using FluxCD.**

DHCP configuration needs to be changed according to your networking setup - [dhcp-config](kubernetes/apps/dhcp/dhcp.yaml)
<br/><br/>

## Variables
The following variables need to be set in terminal:

```bash
export PROXMOX_HOST="https://px.host.com:8006/api2/json"
export PROXMOX_TOKEN_ID='root@pam!fire'
export PROXMOX_TOKEN_SECRET="secret"
export PROXMOX_NODE_NAME="proxmox"
export CLUSTER_NAME="mgmt-cluster"
```

## Packer

Configure variables in [local.pkrvars.hcl](packer/vars/local.pkrvars.hcl)

```bash
cd packer

packer init -upgrade .

packer build -only=release.proxmox.talos -var-file="vars/local.pkrvars.hcl" -var proxmox_username="${PROXMOX_TOKEN_ID}" \
-var proxmox_token="${PROXMOX_TOKEN_SECRET}" -var proxmox_nodename="${PROXMOX_NODE_NAME}" -var proxmox_url="${PROXMOX_HOST}" .
```

<details>
  <summary>Output:</summary>

```bash
release.proxmox.talos: output will be in this color.

==> release.proxmox.talos: Creating VM
==> release.proxmox.talos: No VM ID given, getting next free from Proxmox
==> release.proxmox.talos: Starting VM
==> release.proxmox.talos: Waiting 25s for boot
==> release.proxmox.talos: Typing the boot command
==> release.proxmox.talos: Using SSH communicator to connect: 10.1.1.30
==> release.proxmox.talos: Waiting for SSH to become available...
==> release.proxmox.talos: Connected to SSH!
==> release.proxmox.talos: Provisioning with shell script: /var/folders/p9/q4lh62654_zbp_psdzkf5gj00000gn/T/packer-shell3807895858
==> release.proxmox.talos:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
==> release.proxmox.talos:                                  Dload  Upload   Total   Spent    Left  Speed
==> release.proxmox.talos:   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
==> release.proxmox.talos:   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
==> release.proxmox.talos: 100 75.3M  100 75.3M    0     0  9789k      0  0:00:07  0:00:07 --:--:-- 10.6M
==> release.proxmox.talos: 2551808+0 records in
==> release.proxmox.talos: 2551808+0 records out
==> release.proxmox.talos: 1306525696 bytes (1.3 GB, 1.2 GiB) copied, 14.2868 s, 91.5 MB/s
==> release.proxmox.talos: Stopping VM
==> release.proxmox.talos: Converting VM to template
Build 'release.proxmox.talos' finished after 2 minutes 14 seconds.

==> Wait completed after 2 minutes 14 seconds

==> Builds finished. The artifacts of successful builds are:
--> release.proxmox.talos: A template was created: 101
```
</details>
<br/><br/>

<p align="right">(<a href="#introduction">back to top</a>)</p>

### Manual method

We create an Arch Linux VM in Proxmox. Find the name of system disk, for example - `local-lvm:vm-106-disk-0`, `lvm volume vm-106-disk-0`.
We copy Talos system disk using [talos nocloud image](https://github.com/siderolabs/talos/releases/download/v1.4.2/nocloud-amd64.raw.xz) to this volume.

```bash
cd /tmp
wget https://github.com/siderolabs/talos/releases/download/v1.4.1/nocloud-amd64.raw.xz
xz -d -c nocloud-amd64.raw.xz | dd of=/dev/mapper/vg0-vm--106--disk--0
```

And then stop & convert that VM into the template in Proxmox.

## Terraform

Configure variables in [terraform.tfvars](terraform/terraform.tfvars) 

**!!! Keep apiDomain variable the same = api.cluster.local. Otherwise, Cilium init is going to fail.**

### terraform plan

```bash
cd terraform

terraform plan -var-file="terraform.tfvars" -var proxmox_token_id="${PROXMOX_TOKEN_ID}" \
 -var proxmox_token_secret="${PROXMOX_TOKEN_SECRET}" -var target_node_name="${PROXMOX_NODE_NAME}" \
 -var proxmox_host="${PROXMOX_HOST}" -var cluster_name="${CLUSTER_NAME}"
```

### terraform apply

```bash
terraform apply -auto-approve -var-file="terraform.tfvars" -var proxmox_token_id="${PROXMOX_TOKEN_ID}" \
 -var proxmox_token_secret="${PROXMOX_TOKEN_SECRET}" -var target_node_name="${PROXMOX_NODE_NAME}" \
 -var proxmox_host="${PROXMOX_HOST}" -var cluster_name="${CLUSTER_NAME}"
```

<details>
  <summary>Output:</summary>

```bash
# output truncated
local_sensitive_file.talosconfig: Creation complete after 0s [id=542ee0511df16825d846eed4e0bf4f6ca5fdbe61]
null_resource.kubeconfig: Creating...
null_resource.kubeconfig: Provisioning with 'local-exec'...
null_resource.kubeconfig (local-exec): Executing: ["/bin/sh" "-c" "talosctl kubeconfig --force -n 10.1.1.5 -e 10.1.1.5 --talosconfig ./talosconfig"]
null_resource.kubeconfig: Creation complete after 0s [id=5310785605648426604]
null_resource.kubeconfigapi: Creating...
null_resource.kubeconfigapi: Provisioning with 'local-exec'...
null_resource.kubeconfigapi (local-exec): Executing: ["/bin/sh" "-c" "kubectl --kubeconfig ~/.kube/config config set clusters.mgmt-cluster.server https://10.1.1.20:6443"]
null_resource.kubeconfigapi (local-exec): Property "clusters.mgmt-cluster.server" set.
null_resource.kubeconfigapi: Creation complete after 0s [id=3224005877932970184]

Apply complete! Resources: 17 added, 0 changed, 0 destroyed.

Outputs:

cp = <sensitive>
talosconfig = <sensitive>
worker = <sensitive>
```
</details>
<br/><br/>

After `terraform apply` is completed, within 10 minutes (depends if you use pull cache or not) you should have the following kubectl output:

```bash
kubectl get node -o wide
NAME       STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE         KERNEL-VERSION   CONTAINER-RUNTIME
master-0   Ready    control-plane   2m24s   v1.27.1   10.1.1.5      <none>        Talos (v1.4.2)   6.1.27-talos     containerd://1.6.21
master-1   Ready    control-plane   2m30s   v1.27.1   10.1.1.6      <none>        Talos (v1.4.2)   6.1.27-talos     containerd://1.6.21
master-2   Ready    control-plane   2m45s   v1.27.1   10.1.1.7      <none>        Talos (v1.4.2)   6.1.27-talos     containerd://1.6.21
worker-0   Ready    <none>          2m49s   v1.27.1   10.1.1.8      <none>        Talos (v1.4.2)   6.1.27-talos     containerd://1.6.21
worker-1   Ready    <none>          2m33s   v1.27.1   10.1.1.9      <none>        Talos (v1.4.2)   6.1.27-talos     containerd://1.6.21
worker-2   Ready    <none>          2m31s   v1.27.1   10.1.1.10     <none>        Talos (v1.4.2)   6.1.27-talos     containerd://1.6.21

kubectl get pod -A
NAMESPACE        NAME                                                READY   STATUS    RESTARTS        AGE
cabpt-system     cabpt-controller-manager-bcbb75fd8-fbczg            1/1     Running   0               70s
cacppt-system    cacppt-controller-manager-5b99d8794f-rphl2          1/1     Running   0               70s
capi-system      capi-controller-manager-86c6bfd9b5-g6xk7            1/1     Running   0               70s
cert-manager     cert-manager-555cc9b8b5-8snqq                       1/1     Running   0               106s
cert-manager     cert-manager-cainjector-55c69fbf8-l77qj             1/1     Running   0               106s
cert-manager     cert-manager-webhook-65ddf78f48-mwq74               1/1     Running   0               106s
cilium           cilium-25ltk                                        1/1     Running   0               2m54s
cilium           cilium-8lhqv                                        1/1     Running   0               2m47s
cilium           cilium-dhhk4                                        1/1     Running   0               2m56s
cilium           cilium-kswnj                                        1/1     Running   0               3m8s
cilium           cilium-m9wfj                                        1/1     Running   0               3m12s
cilium           cilium-operator-7496b89b79-cpxkl                    1/1     Running   0               3m13s
cilium           cilium-operator-7496b89b79-fhfhs                    1/1     Running   0               3m13s
cilium           cilium-qcwgq                                        1/1     Running   0               2m53s
cilium           hubble-relay-84c586cc86-7kpts                       1/1     Running   0               3m13s
cilium           hubble-ui-694cf76f4c-pjnv7                          2/2     Running   0               3m12s
csi-proxmox      proxmox-csi-plugin-controller-666957fd94-rpz97      5/5     Running   0               117s
csi-proxmox      proxmox-csi-plugin-node-5gfng                       3/3     Running   2 (106s ago)    117s
csi-proxmox      proxmox-csi-plugin-node-6vqvs                       3/3     Running   0               117s
csi-proxmox      proxmox-csi-plugin-node-kq2l6                       3/3     Running   2 (105s ago)    117s
flux-system      helm-controller-79ff5d8665-6bnxw                    1/1     Running   0               119s
flux-system      image-automation-controller-679b595d96-62lwq        1/1     Running   0               119s
flux-system      image-reflector-controller-9b7d45fc5-bc7gh          1/1     Running   0               119s
flux-system      kustomize-controller-5b658b9864-9b5rv               1/1     Running   0               119s
flux-system      notification-controller-86d886486b-zb497            1/1     Running   0               119s
flux-system      source-controller-6fd5cb556d-kznjv                  1/1     Running   0               116s
kube-system      coredns-d779cc7ff-mmhj7                             1/1     Running   0               3m10s
kube-system      coredns-d779cc7ff-s2kg8                             1/1     Running   0               3m10s
kube-system      coredns-local-87cfn                                 1/1     Running   0               2m29s
kube-system      coredns-local-bs9q4                                 1/1     Running   0               2m19s
kube-system      coredns-local-dgsp6                                 1/1     Running   0               2m27s
kube-system      coredns-local-jmqc5                                 1/1     Running   0               2m26s
kube-system      coredns-local-pmxp9                                 1/1     Running   0               2m54s
kube-system      coredns-local-qsj7z                                 1/1     Running   0               2m39s
kube-system      dhcp-talos-dhcp-server-7855bb8897-998zn             1/1     Running   0               2m
kube-system      kube-apiserver-master-0                             1/1     Running   0               2m8s
kube-system      kube-apiserver-master-1                             1/1     Running   0               2m23s
kube-system      kube-apiserver-master-2                             1/1     Running   0               2m9s
kube-system      kube-controller-manager-master-0                    1/1     Running   1 (3m32s ago)   2m4s
kube-system      kube-controller-manager-master-1                    1/1     Running   2 (3m36s ago)   2m8s
kube-system      kube-controller-manager-master-2                    1/1     Running   1 (3m17s ago)   2m7s
kube-system      kube-scheduler-master-0                             1/1     Running   1 (3m32s ago)   2m6s
kube-system      kube-scheduler-master-1                             1/1     Running   2 (3m37s ago)   112s
kube-system      kube-scheduler-master-2                             1/1     Running   1 (3m17s ago)   2m9s
kube-system      metrics-server-7b4c4d4bfd-x6dzg                     1/1     Running   0               2m51s
kube-system      proxmox-cloud-controller-manager-79c9ff5cf6-xpn6l   1/1     Running   0               2m49s
kube-system      proxmox-operator-5c79f67c66-w9g72                   1/1     Running   0               117s
kube-system      talos-cloud-controller-manager-776fdbd456-wtmjk     1/1     Running   0               2m46s
metallb-system   controller-7948676b95-w58sw                         1/1     Running   0               2m55s
metallb-system   speaker-9h28g                                       1/1     Running   0               2m10s
metallb-system   speaker-dkrvr                                       1/1     Running   0               2m11s
metallb-system   speaker-drxxr                                       1/1     Running   0               2m11s
metallb-system   speaker-fz8ls                                       1/1     Running   0               2m10s
metallb-system   speaker-j2v4g                                       1/1     Running   0               2m10s
metallb-system   speaker-nbpl7                                       1/1     Running   0               2m10s
sidero-system    caps-controller-manager-5b4b95bcdb-74bvb            1/1     Running   0               70s
sidero-system    sidero-controller-manager-7d5b96cf6d-tppq6          4/4     Running   0               70s
```
### terraform output for talosconfig & kubeconfig can be checked if needed

```bash
terraform output -raw talosconfig
terraform output -raw kubeconfig
```

### CSI testing

Storageclasses should be already configured in the cluster:
```bash
kubectl get sc
NAME               PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
proxmox-data       csi.proxmox.sinextra.dev   Delete          WaitForFirstConsumer   true                   6m33s
proxmox-data-xfs   csi.proxmox.sinextra.dev   Delete          WaitForFirstConsumer   true                   6m33s
```

Let's apply a test Pod with volume attached and check on that:

`kubectl apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/test-pod-ephemeral.yaml`

```bash
kubectl apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/test-pod-ephemeral.yaml
pod/test created

kubectl -n default get pods,pvc
NAME       READY   STATUS    RESTARTS   AGE
pod/test   1/1     Running   0          70s

NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS       AGE
persistentvolumeclaim/test-pvc   Bound    pvc-41b1aea6-fa99-4ad3-b28d-57f1ce4a85aa   1Gi        RWO            proxmox-data-xfs   70s

---
kubectl describe pv pvc-41b1aea6-fa99-4ad3-b28d-57f1ce4a85aa
Name:              pvc-41b1aea6-fa99-4ad3-b28d-57f1ce4a85aa
Labels:            <none>
Annotations:       pv.kubernetes.io/provisioned-by: csi.proxmox.sinextra.dev
                   volume.kubernetes.io/provisioner-deletion-secret-name:
                   volume.kubernetes.io/provisioner-deletion-secret-namespace:
Finalizers:        [kubernetes.io/pv-protection external-attacher/csi-proxmox-sinextra-dev]
StorageClass:      proxmox-data-xfs
Status:            Bound
Claim:             default/test-pvc
Reclaim Policy:    Delete
Access Modes:      RWO
VolumeMode:        Filesystem
Capacity:          1Gi
Node Affinity:
  Required Terms:
    Term 0:        topology.kubernetes.io/region in [cluster-1]
                   topology.kubernetes.io/zone in [proxmox]
Message:
Source:
    Type:              CSI (a Container Storage Interface (CSI) volume source)
    Driver:            csi.proxmox.sinextra.dev
    FSType:            xfs
    VolumeHandle:      cluster-1/proxmox/vms/vm-9999-pvc-41b1aea6-fa99-4ad3-b28d-57f1ce4a85aa
    ReadOnly:          false
    VolumeAttributes:      storage=vms
                           storage.kubernetes.io/csiProvisionerIdentity=1683735975451-8081-csi.proxmox.sinextra.dev
Events:                <none>
```

Try StatefulSet:

`kubectl apply -f https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/test-statefulset.yaml`

```bash
kubectl -n default get pods,pvc -owide                                                                                                                                                                                                                                                          4s ⎈ admin@mgmt-cluster
NAME         READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
pod/test-0   1/1     Running   0          57s   10.244.3.95    worker-2   <none>           <none>
pod/test-1   1/1     Running   0          57s   10.244.0.119   worker-0   <none>           <none>
pod/test-2   1/1     Running   0          57s   10.244.2.234   worker-1   <none>           <none>

NAME                                   STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE   VOLUMEMODE
persistentvolumeclaim/storage-test-0   Bound     pvc-d8be278f-ffee-49c3-b303-10fc2ebd79ae   1Gi        RWO            proxmox-data   57s   Filesystem
persistentvolumeclaim/storage-test-1   Bound     pvc-a7b73455-1ae2-4fb5-a7ca-1a671e81491c   1Gi        RWO            proxmox-data   57s   Filesystem
persistentvolumeclaim/storage-test-2   Bound     pvc-f7ab10a6-50af-40d4-b704-8fefb0d1bff9   1Gi        RWO            proxmox-data   57s   Filesystem
```

<p align="right">(<a href="#introduction">back to top</a>)</p>

## Sidero Bootstrap

If you check your Proxmox UI, you might find 2 new VM's already running in there. What we can see in the Management k8s cluster though:

```bash
kubectl get qemu

NAME              STATUS   POWER   CLUSTER     NODE      VMID
sidero-master-1   SYNCED   ON      cluster-1   proxmox   108
sidero-worker-1   SYNCED   ON      cluster-1   proxmox   109
---

kubectl get servers

NAME                                   HOSTNAME    ACCEPTED   CORDONED   ALLOCATED   CLEAN   POWER   AGE
f0ac3f32-ee63-11ed-a05b-0242ac120003   10.1.1.52   true                              true    on      12m
fe4fadea-ee63-11ed-a05b-0242ac120003   10.1.1.53   true                              true    on      12m
---

kubectl get serverclasses

AME               AVAILABLE                                                                         IN USE   AGE
any                ["f0ac3f32-ee63-11ed-a05b-0242ac120003","fe4fadea-ee63-11ed-a05b-0242ac120003"]   []       14m
master-cluster-0   []                                                                                []       14m
worker-cluster-0   []                                                                                []       14m
---

kubectl get cluster 

NAME        PHASE         AGE   VERSION
cluster-0   Provisioned   14m
---

kubectl get TalosControlPlane

NAME           READY   INITIALIZED   REPLICAS   READY REPLICAS   UNAVAILABLE REPLICAS
cluster-0-cp                         1                           1
---

kubectl get MachineDeployment

NAME                CLUSTER     REPLICAS   READY   UPDATED   UNAVAILABLE   PHASE       AGE   VERSION
cluster-0-workers   cluster-0   1                  1         1             ScalingUp   14m   v1.27.1

```

As mentioned before, all of these manifests were applied and synced via FluxCD from [cluster-0](kubernetes/apps/clusters/cluster-0/manifests/).

If you look at ServerClasses for [masters](kubernetes/apps/clusters/cluster-0/manifests/master-dev-sc.yaml) and [workers](kubernetes/apps/clusters/cluster-0/manifests/worker-dev-sc.yaml), `labelSelectors` are specified in there hence we need to apply labels to the `servers` in order to start bootstrapping a new k8s cluster.

```bash
kubectl label servers fe4fadea-ee63-11ed-a05b-0242ac120003 worker-dev=true
kubectl label servers f0ac3f32-ee63-11ed-a05b-0242ac120003 master-dev=true

server.metal.sidero.dev/fe4fadea-ee63-11ed-a05b-0242ac120003 labeled
server.metal.sidero.dev/f0ac3f32-ee63-11ed-a05b-0242ac120003 labeled
```

At this time, we can see that both servers are now In Use, which means that cluster creation is initiliazed:

```bash
kubectl get serverclasses

NAME               AVAILABLE   IN USE                                                                            AGE
any                []          ["f0ac3f32-ee63-11ed-a05b-0242ac120003","fe4fadea-ee63-11ed-a05b-0242ac120003"]   22m
master-cluster-0   []          ["f0ac3f32-ee63-11ed-a05b-0242ac120003"]                                          22m
worker-cluster-0   []          ["fe4fadea-ee63-11ed-a05b-0242ac120003"]                                          22m
```

Now, lets fetch talosconfig and kubeconfig from the cluster:

```bash
kubectl get talosconfig -o yaml $(kubectl get talosconfig --no-headers | awk 'NR==1{print $1}') -o jsonpath='{.status.talosConfig}' > cluster-0.yaml

talosctl --talosconfig cluster-0.yaml kubeconfig --force -n 10.1.1.40 -e 10.1.1.40
```

Due to the fact that we use Cilium for all of our clusters with `api.cluster.local`, we want to change the API endpoint to the Talos cluster VIP, which in my terraform settings is set to 10.1.1.40:

```bash
kubectl --kubeconfig ~/.kube/config config set clusters.cluster-0.server https://10.1.1.40:6443

Property "clusters.cluster-0.server" set.
```

At that point, we have a fully working cluster bootstrapped and provisioned via Sidero and FluxCD:

```bash
kubectl get node

NAME            STATUS   ROLES           AGE     VERSION
talos-5o3-l4b   Ready    <none>          3m2s    v1.27.1
talos-svd-m63   Ready    control-plane   2m56s   v1.27.1
---

kubectl get pod -A

NAMESPACE        NAME                                    READY   STATUS    RESTARTS        AGE
cilium           cilium-c878h                            1/1     Running   0               3m7s
cilium           cilium-operator-7496b89b79-7zx66        1/1     Running   0               3m13s
cilium           cilium-operator-7496b89b79-ff4vt        1/1     Running   0               3m13s
cilium           cilium-rhqxv                            1/1     Running   0               3m1s
cilium           hubble-relay-84c586cc86-z82jt           1/1     Running   0               3m13s
cilium           hubble-ui-694cf76f4c-bzlq2              2/2     Running   0               3m13s
kube-system      coredns-5665966b56-7zz8m                1/1     Running   0               3m13s
kube-system      coredns-5665966b56-vbtwq                1/1     Running   0               3m13s
kube-system      coredns-local-7pls2                     1/1     Running   0               2m36s
kube-system      coredns-local-qlkcg                     1/1     Running   0               2m34s
kube-system      kube-apiserver-talos-svd-m63            1/1     Running   0               2m39s
kube-system      kube-controller-manager-talos-svd-m63   1/1     Running   2 (3m44s ago)   2m17s
kube-system      kube-scheduler-talos-svd-m63            1/1     Running   2 (3m44s ago)   2m1s
kube-system      kubelet-csr-approver-7759f94756-bkhzr   1/1     Running   0               3m13s
kube-system      metrics-server-7b4c4d4bfd-h2sc6         1/1     Running   0               3m8s
metallb-system   controller-7948676b95-947g5             1/1     Running   0               3m12s
metallb-system   speaker-6kzj8                           1/1     Running   0               2m34s
metallb-system   speaker-m7d7z                           1/1     Running   0               2m36s
```

### Scaling
In case if you want to add more nodes, you can add QEMU objects in [vms.yaml](kubernetes/apps/clusters/cluster-0/manifests/vms.yaml) manifest. Even though we have all resources in the management cluster, we can't scale the nodes using [kubectl command like here](https://www.sidero.dev/v0.5/getting-started/scale-workload/) thats because we use FluxCD to sync our manifests in the cluster. Therefore, to add more worker nodes we need to scale replicas in [cluster-0.yaml](kubernetes/apps/clusters/cluster-0/manifests/cluster-0.yaml) manifest `MachineDeployment` object. Additionally, all of these new nodes need to be labeled with `worker-dev=true` `labelSelectors`.

Likewise, if you add more nodes via Proxmox-operator, you can either set your custom uuid's for the nodes or delete the whole `smbios1` part.

`smbios1: "uuid=f0ac3f32-ee63-11ed-a05b-0242ac120003,manufacturer=MTIz,product=MTIz,version=MTIz,serial=MTIz,sku=MTIz,family=MTIz,base64=1"`

### New clusters

If you need to create a new cluster, follow this [doc](https://www.sidero.dev/v0.5/getting-started/create-workload/). It will be the same process of running these commands, and once cluster-1 manifest is generated you can add it to FluxCD git repo.

```bash
export CONTROL_PLANE_SERVERCLASS=master-cluster-1
export WORKER_SERVERCLASS=worker-cluster-1
export TALOS_VERSION=v1.3.0
export KUBERNETES_VERSION=v1.27.1
export CONTROL_PLANE_PORT=6443
export CONTROL_PLANE_ENDPOINT=api.cluster.local

clusterctl generate cluster cluster-1 -i sidero:v0.5.8 > cluster-1.yaml
```

<br/><br/>

<p align="right">(<a href="#introduction">back to top</a>)</p>

## Teraform destroy

```bash
terraform destroy -refresh=false -auto-approve -var-file="terraform.tfvars" -var proxmox_token_id="${PROXMOX_TOKEN_ID}" \
 -var proxmox_token_secret="${PROXMOX_TOKEN_SECRET}" -var target_node_name="${PROXMOX_NODE_NAME}" -var proxmox_host="${PROXMOX_HOST}" -var cluster_name="${CLUSTER_NAME}"
```

Bear in mind that if you run `terraform destroy`, it's not going to delete VM's which were provisioned by Proxmox Operator/FluxCD. You would need to stop sync in FluxCD, and destroy those machines via `kubectl delete qemu vm-name` command.
<br/><br/>

References
============
https://www.sidero.dev/v0.5/getting-started/

https://www.talos.dev/v1.4/talos-guides/install/cloud-platforms/nocloud/

https://github.com/sergelogvinov/terraform-talos

### Author's blog

https://bnovickovs.me/

### terraform gitignore template

```bash
# Local .terraform directories
**/.terraform/*

# .tfstate files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Ignore override files as they are usually used to override resources locally and so
# are not checked in
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Include override files you do wish to add to version control using negated pattern
# !example_override.tf

# Include tfplan files to ignore the plan output of command: terraform plan -out=tfplan
# example: *tfplan*

# Ignore CLI configuration files
.terraformrc
terraform.rc
.terraform.lock.hcl

talosconfig
kubeconfig
```