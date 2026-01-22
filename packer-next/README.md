# Packer Next - Ubuntu 24.04 Cloud Image

使用 Ubuntu Cloud Image 构建 Proxmox VM 模板，比 ISO 安装方式快得多。

## 对比

| 方式 | 构建时间 | 特点 |
|------|----------|------|
| ISO + autoinstall | 15-30 分钟 | 完全自定义安装 |
| **Cloud Image** | **2-5 分钟** | 预装系统，只需配置 |

## 快速开始

### 1. 导入 Cloud Image 到 Proxmox

首先需要在 **Proxmox 节点**上运行导入脚本：

```bash
# 将脚本复制到 Proxmox 节点
scp scripts/import-cloud-image.sh root@pve3.gzpolpo.net:/tmp/

# 在 Proxmox 节点上执行
ssh root@pve3.gzpolpo.net
chmod +x /tmp/import-cloud-image.sh
/tmp/import-cloud-image.sh
```

或者手动执行：

```bash
# 下载 Cloud Image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# 创建 VM
qm create 9000 --name ubuntu-2404-cloud-base --memory 2048 --net0 virtio,bridge=vmbr0

# 导入磁盘
qm importdisk 9000 noble-server-cloudimg-amd64.img local-lvm

# 配置 VM
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm set 9000 --ciuser ubuntu
qm set 9000 --sshkeys ~/.ssh/id_rsa.pub
qm set 9000 --ipconfig0 ip=dhcp

# 扩展磁盘
qm resize 9000 scsi0 20G

# 转为模板
qm template 9000
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 填入 Proxmox API 信息
```

### 3. 构建最终模板

```bash
# 加载环境变量
source .env

# 初始化 Packer 插件
packer init .

# 验证配置
packer validate -var-file="config.pkrvars.hcl" .

# 构建模板
packer build -var-file="config.pkrvars.hcl" .
```

## 目录结构

```
packer-next/
├── ubuntu-24.04-cloud.pkr.hcl  # 主 Packer 配置（使用 proxmox-clone）
├── variables.pkr.hcl            # 变量定义
├── config.pkrvars.hcl           # 变量值配置
├── .env.example                 # 环境变量模板
├── README.md                    # 本文档
└── scripts/
    ├── import-cloud-image.sh    # Cloud Image 导入脚本
    ├── setup.sh                 # 系统配置脚本
    ├── cleanup.sh               # 清理脚本
    ├── route-switch.sh          # 路由切换脚本
    ├── mount-nfs-share.sh       # NFS 挂载脚本
    └── 99-pve.cfg               # Cloud-init 配置
```

## 配置说明

### config.pkrvars.hcl

主要配置项：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `proxmox_node` | Proxmox 节点名 | `pve3` |
| `cloud_image_template_name` | Cloud Image 基础模板名 | `ubuntu-2404-cloud-base` |
| `cloud_image_template_id` | 基础模板 VM ID | `9000` |
| `template_id` | 最终模板 VM ID | `999` |
| `ssh_username` | SSH 用户名 | `ubuntu` |
| `ssh_private_key_file` | SSH 私钥路径 | `~/.ssh/id_rsa` |

### SSH 认证

Cloud Image 默认使用 SSH 密钥认证，需要确保：

1. Proxmox 节点上有你的 SSH 公钥（`~/.ssh/id_rsa.pub`）
2. 本地有对应的私钥（`~/.ssh/id_rsa`）

## 工作流程

```
┌─────────────────────────────────────────────────────────────┐
│                      Proxmox 节点                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 导入 Cloud Image                                         │
│     ┌──────────────────────┐                                │
│     │ ubuntu-2404-cloud-   │  (VM ID: 9000)                 │
│     │ base (模板)           │  只包含基础 Ubuntu 系统        │
│     └──────────┬───────────┘                                │
│                │                                             │
│                │ Packer clone                               │
│                ▼                                             │
│     ┌──────────────────────┐                                │
│     │ 临时 VM              │  运行 provisioner:             │
│     │                       │  - 配置镜像源                  │
│     │                       │  - 安装软件包                  │
│     │                       │  - 预装 VS Code Server        │
│     └──────────┬───────────┘                                │
│                │                                             │
│                │ 转换为模板                                  │
│                ▼                                             │
│     ┌──────────────────────┐                                │
│     │ ubuntu-2404-coder-   │  (VM ID: 999)                  │
│     │ template (最终模板)   │  可供 Terraform/Coder 使用     │
│     └──────────────────────┘                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 与旧版 (packer/) 的区别

| 特性 | packer/ (ISO) | packer-next/ (Cloud Image) |
|------|---------------|----------------------------|
| 构建源 | Ubuntu ISO | Cloud Image |
| Packer 源类型 | `proxmox-iso` | `proxmox-clone` |
| 构建时间 | 15-30 分钟 | 2-5 分钟 |
| autoinstall | 需要 | 不需要 |
| HTTP 服务器 | 需要 | 不需要 |
| SSH 认证 | 密码 | 密钥 |
| 灵活性 | 高（可自定义分区等） | 中（使用预设分区） |

## 故障排除

### SSH 连接失败

1. 确认 Cloud Image 基础模板已正确配置 SSH 公钥
2. 检查私钥权限：`chmod 600 ~/.ssh/id_rsa`
3. 尝试手动连接：`ssh ubuntu@<vm-ip>`

### Cloud-init 未完成

1. 检查 VM 控制台输出
2. 查看日志：`sudo cat /var/log/cloud-init.log`

### 模板克隆失败

1. 确认基础模板存在：`qm list | grep 9000`
2. 确认存储池有足够空间
