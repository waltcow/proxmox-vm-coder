terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

provider "coder" {}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  # 需要 SSH 连接以便上传文件到 Proxmox
  ssh {
    username = var.proxmox_ssh_user
    password = var.proxmox_password

    node {
      name    = var.proxmox_node
      address = var.proxmox_host
    }
  }
}

variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}


variable "proxmox_host" {
  description = "用于 SSH 连接的 Proxmox 节点 IP 或 DNS"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox 密码（用于 SSH 连接）"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_user" {
  description = "Proxmox 节点上的 SSH 用户名"
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "目标 Proxmox 节点"
  type        = string
  default     = "pve"
}
variable "disk_storage" {
  description = "磁盘存储（例如 local-lvm）"
  type        = string
  default     = "local-lvm"
}

variable "snippet_storage" {
  description = "支持 Snippets 内容的存储"
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "网桥（例如 vmbr0）"
  type        = string
  default     = "vmbr0"
}

variable "vlan" {
  description = "VLAN 标签（0 表示无）"
  type        = number
  default     = 0
}

variable "clone_template_vmid" {
  description = "要克隆的 cloud-init 基础模板的 VMID"
  type        = number
}

variable "code_server_download_url" {
  description = "code-server tar.gz 下载地址（HTTP/HTTPS）"
  type        = string
  default     = ""
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU 核心数"
  type         = "number"
  default      = 2
  mutable      = true
}

data "coder_parameter" "memory_mb" {
  name         = "memory_mb"
  display_name = "内存 (MB)"
  type         = "number"
  default      = 4096
  mutable      = true
}

data "coder_parameter" "disk_size_gb" {
  name         = "disk_size_gb"
  display_name = "磁盘大小 (GB)"
  type         = "number"
  default      = 20
  mutable      = true
  validation {
    min       = 10
    max       = 100
    monotonic = "increasing"
  }
}

resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"

  env = {
    GIT_AUTHOR_NAME  = data.coder_workspace_owner.me.name
    GIT_AUTHOR_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script_behavior = "non-blocking"
  startup_script          = <<-EOT
    set -e
    # 在此处添加任何启动脚本
  EOT

  metadata {
    display_name = "CPU 使用率"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
    order        = 1
  }

  metadata {
    display_name = "内存使用率"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
    order        = 2
  }

  metadata {
    display_name = "磁盘使用率"
    key          = "disk_usage"
    script       = "coder stat disk"
    interval     = 600
    timeout      = 30
    order        = 3
  }
}

locals {
  hostname         = lower(data.coder_workspace.me.name)
  vm_name          = "coder-${lower(data.coder_workspace_owner.me.name)}-${local.hostname}"
  snippet_filename = "${local.vm_name}.yml"
  base_user        = replace(replace(replace(lower(data.coder_workspace_owner.me.name), " ", "-"), "/", "-"), "@", "-")             # 避免用户名中的特殊字符
  linux_user       = contains(["root", "admin", "daemon", "bin", "sys"], local.base_user) ? "${local.base_user}1" : local.base_user # 避免与系统用户冲突

  rendered_user_data = templatefile("${path.module}/cloud-init/user-data.tftpl", {
    coder_token           = coder_agent.main.token
    coder_init_script_b64 = base64encode(coder_agent.main.init_script)
    hostname              = local.vm_name
    linux_user            = local.linux_user
  })
}

resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = var.snippet_storage
  node_name    = var.proxmox_node

  source_raw {
    data      = local.rendered_user_data
    file_name = local.snippet_filename
  }
}

resource "proxmox_virtual_environment_vm" "workspace" {
  name      = local.vm_name
  node_name = var.proxmox_node

  clone {
    node_name = var.proxmox_node
    vm_id     = var.clone_template_vmid
    full      = false
    retries   = 5
  }

  agent {
    enabled = true
  }

  on_boot = true
  started = true

  startup {
    order = 1
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0", "ide2"]

  memory {
    dedicated = data.coder_parameter.memory_mb.value
  }

  cpu {
    cores   = data.coder_parameter.cpu_cores.value
    sockets = 1
    type    = "host"
  }

  network_device {
    bridge  = var.bridge
    model   = "virtio"
    vlan_id = var.vlan == 0 ? null : var.vlan
  }

  vga {
    type = "std"
  }

  serial_device {
    device = "socket"
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.disk_storage
    size         = data.coder_parameter.disk_size_gb.value
  }

  initialization {
    type         = "nocloud"
    datastore_id = var.disk_storage

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  tags = ["coder", "workspace", local.vm_name]

  depends_on = [proxmox_virtual_environment_file.cloud_init_user_data]
}

module "code-server" {
  count           = data.coder_workspace.me.start_count
  source          = "./modules/code-server"
  agent_id        = coder_agent.main.id
  additional_args = "--disable-workspace-trust"
  download_url       = var.code_server_download_url
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "1.0.32"
  agent_id = coder_agent.main.id
}