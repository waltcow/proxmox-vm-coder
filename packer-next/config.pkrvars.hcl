# Packer 配置变量文件
# 此文件包含非敏感的配置信息，可以提交到 git

# ============================================
# Proxmox 节点配置
# ============================================
proxmox_node = "pve3"

# ============================================
# 存储配置
# ============================================
storage_pool   = "local-lvm"
network_bridge = "vmbr0"

# ============================================
# Cloud Image 基础模板
# ============================================
# 需要先运行 scripts/import-cloud-image.sh 导入
cloud_image_template_name = "ubuntu-2404-cloud-base"
cloud_image_template_id   = 9000

# ============================================
# 最终模板配置
# ============================================
# 模板 ID 与 Terraform 的 clone_template_vmid 保持一致
template_id          = 999
template_name        = "ubuntu-2404-coder-template"
template_description = "Ubuntu 24.04 (Cloud Image) with Tsinghua mirrors and pre-installed tools for Coder workspaces"

# ============================================
# VM 硬件配置
# ============================================
cpu_cores = 2
memory    = 4096
disk_size = "20G"

# ============================================
# SSH 配置
# ============================================
ssh_username         = "ubuntu"
ssh_private_key_file = "~/.ssh/id_pve3"
ssh_timeout          = "10m"
