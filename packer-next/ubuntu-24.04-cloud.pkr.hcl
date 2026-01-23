
# Packer 主构建配置文件
# 使用 Ubuntu 24.04 Cloud Image 构建 Proxmox VM 模板
# 比 ISO 安装方式快得多（约 2-5 分钟 vs 15-30 分钟）

packer {
  required_version = ">= 1.9.0"
  required_plugins {
    proxmox = {
      version = ">= 1.2.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ============================================
# 使用 proxmox-clone 从已导入的 cloud image 克隆
# ============================================
source "proxmox-clone" "ubuntu2404-cloud" {
  # ============================================
  # Proxmox 连接配置
  # ============================================
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ============================================
  # 克隆配置
  # ============================================
  # 克隆已导入的 cloud image 基础模板
  clone_vm   = var.cloud_image_template_name
  full_clone = true

  # ============================================
  # VM 配置
  # ============================================
  vm_id                = var.template_id
  vm_name              = var.template_name
  template_description = var.template_description

  # ============================================
  # 硬件配置
  # ============================================
  cores  = var.cpu_cores
  memory = var.memory
  os     = "l26" # Linux Kernel 2.6+
  scsi_controller = "virtio-scsi-pci"

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

  # VGA 配置
  vga {
    type = "std"
  }

  # QEMU Guest Agent
  qemu_agent = true

  # ============================================
  # SSH 配置
  # ============================================
  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout
  ssh_host             = "192.168.50.250"
  
  # 使用 QEMU Guest Agent 获取 IP（需要 agent 启动后才能连接）
  # 或者可以通过 cloud-init 配置固定 IP
  ssh_agent_auth = false

  # ============================================
  # 模板配置
  # ============================================
  template_name = var.template_name
  onboot        = false
}

build {
  sources = ["source.proxmox-clone.ubuntu2404-cloud"]

  # ============================================
  # Provisioner 1: 等待 cloud-init 完成
  # ============================================
  provisioner "shell" {
    inline = [
      "echo '==> Waiting for cloud-init to complete...'",
      "sudo cloud-init status || true",
      "sudo cloud-init status --wait || true",
      "echo '==> Cloud-init completed'"
    ]
  }

  # ============================================
  # Provisioner 2: 上传脚本文件
  # ============================================
  provisioner "file" {
    source      = "${path.root}/scripts"
    destination = "/tmp"
  }

  # ============================================
  # Provisioner 3: 配置系统（镜像源 + 安装软件）
  # ============================================
  provisioner "shell" {
    script = "scripts/setup.sh"
  }

  # ============================================
  # Provisioner 4: 上传 Proxmox datasource 配置
  # ============================================
  provisioner "file" {
    source      = "${path.root}/scripts/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }

  # ============================================
  # Provisioner 5: 移动配置文件到正确位置
  # ============================================
  provisioner "shell" {
    inline = [
      "echo '==> Installing Proxmox cloud-init datasource configuration...'",
      "sudo mv /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "echo '==> Configuration installed successfully'"
    ]
  }

  # ============================================
  # Provisioner 6: 清理系统
  # ============================================
  provisioner "shell" {
    script = "scripts/cleanup.sh"
  }
}
