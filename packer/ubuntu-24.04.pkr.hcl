# Packer 主构建配置文件
# 用于从 Ubuntu 24.04 ISO 构建 Proxmox VM 模板

packer {
  required_version = ">= 1.9.0"
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-iso" "ubuntu2404" {
  # ============================================
  # Proxmox 连接配置
  # ============================================
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ============================================
  # VM 基础配置
  # ============================================
  vm_id                = var.template_id
  vm_name              = var.template_name
  template_description = var.template_description

  # ============================================
  # ISO 配置
  # ============================================
  boot_iso {
    type         = "scsi"
    iso_file     = "${var.iso_storage_pool}:iso/${var.iso_file}"
    iso_checksum = var.iso_checksum
    unmount      = true
  }

  # ============================================
  # 硬件配置
  # ============================================
  cores  = var.cpu_cores
  memory = var.memory
  os     = "l26" # Linux Kernel 2.6+

  # ============================================
  # 存储配置
  # ============================================
  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.storage_pool
    format       = "raw"
    cache_mode   = "writeback"
    io_thread    = true
  }

  # ============================================
  # 网络配置
  # ============================================
  network_adapters {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = false
  }

  # ============================================
  # Cloud-init 配置
  # ============================================
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # VGA 和串口配置（cloud-init 需要）
  vga {
    type = "std"  # 使用标准 VGA，noVNC 可以看到输出
  }

  serials = ["socket"]

  # QEMU Guest Agent
  qemu_agent = true

  # ============================================
  # Boot 配置
  # ============================================
  boot_wait = "10s"

  # Boot command（使用编辑模式，比 GRUB 命令行更可靠）
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---",
    "<f10><wait>"
  ]

  # ============================================
  # HTTP 服务器配置（提供 autoinstall 配置）
  # ============================================
  # 使用 http_content 块动态生成 user-data（支持模板变量）
  http_content = {
    "/user-data" = templatefile("${path.root}/http/user-data.pkrtpl.hcl", {
      ssh_username = var.ssh_username
      ssh_password = var.ssh_password
    })
    "/meta-data" = file("${path.root}/http/meta-data")
  }

  http_bind_address = "0.0.0.0"
  http_port_min     = 8802
  http_port_max     = 8802

  # ============================================
  # SSH 配置
  # ============================================
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = var.ssh_timeout
  ssh_handshake_attempts = 50
  ssh_pty                = true

  # ============================================
  # 模板配置
  # ============================================
  template_name = var.template_name
  onboot        = false
}

build {
  sources = ["source.proxmox-iso.ubuntu2404"]

  # ============================================
  # Provisioner 1: 等待 cloud-init 完成
  # ============================================
  provisioner "shell" {
    inline = [
      "echo '==> Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo '==> Cloud-init completed successfully'"
    ]
  }

  # ============================================
  # Provisioner 2: 配置系统（镜像源 + 安装软件）
  # ============================================
  provisioner "shell" {
    script = "scripts/setup.sh"
  }

  # ============================================
  # Provisioner 3: 上传 Proxmox datasource 配置
  # ============================================
  provisioner "file" {
    source      = "scripts/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }

  # ============================================
  # Provisioner 4: 移动配置文件到正确位置
  # ============================================
  provisioner "shell" {
    inline = [
      "echo '==> Installing Proxmox cloud-init datasource configuration...'",
      "sudo mv /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "echo '==> Configuration installed successfully'"
    ]
  }

  # ============================================
  # Provisioner 5: 清理系统
  # ============================================
  provisioner "shell" {
    script = "scripts/cleanup.sh"
  }
}
