# Packer 变量定义文件
# 用于构建 Ubuntu 24.04 Proxmox 模板（Cloud Image 方式）

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

# ============================================
# Cloud Image 基础模板配置
# ============================================
variable "cloud_image_template_name" {
  type        = string
  description = "已导入的 Cloud Image 基础模板名称（需要先在 Proxmox 中导入）"
  default     = "ubuntu-2404-cloud-base"
}

variable "cloud_image_template_id" {
  type        = number
  description = "Cloud Image 基础模板的 VM ID"
  default     = 9000
}

# ============================================
# 目标模板配置
# ============================================
variable "template_id" {
  type        = number
  description = "最终模板 VM ID（与 Terraform 的 clone_template_vmid 保持一致）"
  default     = 999
}

variable "template_name" {
  type        = string
  description = "最终模板名称"
  default     = "ubuntu-2404-coder-template"
}

variable "template_description" {
  type        = string
  description = "模板描述"
  default     = "Ubuntu 24.04 template (Cloud Image) with Tsinghua mirrors and pre-installed tools for Coder"
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
  description = "磁盘大小（用于扩展 cloud image 磁盘）"
  default     = "20G"
}

variable "network_bridge" {
  type        = string
  description = "网络桥接"
  default     = "vmbr0"
}

# ============================================
# SSH 配置
# ============================================
variable "ssh_username" {
  type        = string
  description = "SSH 用户名（cloud-init 创建的用户）"
  default     = "ubuntu"
}

variable "ssh_private_key_file" {
  type        = string
  description = "SSH 私钥文件路径"
  default     = "~/.ssh/id_rsa"
}

variable "ssh_timeout" {
  type        = string
  description = "SSH 连接超时时间"
  default     = "10m"
}

variable "ssh_host" {
  type        = string
  description = "SSH 连接主机 IP（如果无法自动获取）"
  default     = "192.168.50.250"
}

variable "vm_os" {
  type        = string
  description = "操作系统类型"
  default     = "l26"
}

variable "vm_vga_type" {
  type        = string
  description = "显卡类型"
  default     = "std"
}
