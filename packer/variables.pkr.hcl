# Packer 变量定义文件
# 用于构建 Ubuntu 24.04 Proxmox 模板

# ============================================
# Proxmox 连接配置
# ============================================
variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL"
  default     = env("PROXMOX_API_URL")
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API Token ID"
  sensitive   = true
  default     = env("PROXMOX_API_TOKEN_ID")
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API Token Secret"
  sensitive   = true
  default     = env("PROXMOX_API_TOKEN_SECRET")
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox 节点名称"
  default     = "pve3"
}

# ============================================
# 存储配置
# ============================================
variable "storage_pool" {
  type        = string
  description = "VM 磁盘存储池名称"
  default     = "local-lvm"
}

variable "iso_storage_pool" {
  type        = string
  description = "ISO 文件存储池"
  default     = "local"
}

# ============================================
# 模板配置
# ============================================
variable "template_id" {
  type        = number
  description = "模板 VM ID（与 Terraform 的 clone_template_vmid 保持一致）"
  default     = 999
}

variable "template_name" {
  type        = string
  description = "模板名称"
  default     = "ubuntu-2404-coder-template"
}

variable "template_description" {
  type        = string
  description = "模板描述"
  default     = "Ubuntu 24.04 template with Tsinghua mirrors and pre-installed tools (curl, git, jq) for Coder"
}

# ============================================
# VM 硬件配置
# ============================================
variable "cpu_cores" {
  type        = number
  description = "CPU 核心数"
  default     = 2
}

variable "memory" {
  type        = number
  description = "内存大小 (MB)"
  default     = 4096
}

variable "disk_size" {
  type        = string
  description = "磁盘大小"
  default     = "20G"
}

variable "network_bridge" {
  type        = string
  description = "网络桥接"
  default     = "vmbr0"
}

# ============================================
# Ubuntu ISO 配置
# ============================================
variable "iso_file" {
  type        = string
  description = "Ubuntu ISO 文件名（需预先上传到 Proxmox 的 iso_storage_pool 中）"
  default     = "ubuntu-24.04.3-live-server-amd64.iso"
}

variable "iso_checksum" {
  type        = string
  description = "ISO SHA256 校验和（从 https://releases.ubuntu.com/24.04.3/SHA256SUMS 获取）"
  default     = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
}

# ============================================
# SSH 配置
# ============================================
variable "ssh_username" {
  type        = string
  description = "SSH 用户名（由 autoinstall 创建，仅用于 provisioning）"
  default     = "packer"
}

variable "ssh_password" {
  type        = string
  description = "SSH 密码（仅用于 provisioning，模板清理后会删除 packer 用户）"
  sensitive   = true
  default     = "packer"
}

variable "ssh_timeout" {
  type        = string
  description = "SSH 连接超时时间"
  default     = "20m"
}
