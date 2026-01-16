# Packer 配置变量文件
# 此文件包含非敏感的配置信息，可以提交到 git

# ============================================
# Proxmox 节点配置
# ============================================
proxmox_node = "pve3"

# ============================================
# 存储配置
# ============================================
storage_pool     = "local-lvm"
iso_storage_pool = "local"
network_bridge   = "vmbr0"

# ============================================
# 模板配置
# ============================================
# 模板 ID 与 Terraform 的 clone_template_vmid 保持一致
template_id          = 999
template_name        = "ubuntu-2404-coder-template"
template_description = "Ubuntu 24.04 with Tsinghua mirrors and pre-installed tools (curl, git, jq, proxychains4) for Coder workspaces"

# ============================================
# VM 硬件配置
# ============================================
cpu_cores = 2
memory    = 4096
disk_size = "20G"

# ============================================
# Ubuntu ISO 配置
# ============================================
# 确保此 ISO 已上传到 Proxmox 的 local:iso/ 存储
iso_file = "ubuntu-24.04.3-live-server-amd64.iso"

# ISO SHA256 校验和
# 从 https://releases.ubuntu.com/24.04.3/SHA256SUMS 获取
iso_checksum = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"

# ============================================
# SSH 配置
# ============================================
ssh_username = "packer"
ssh_timeout  = "20m"
