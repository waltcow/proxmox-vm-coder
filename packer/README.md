# Packer - Ubuntu 24.04 Proxmox 模板构建

本目录包含使用 Packer 构建 Ubuntu 24.04 Proxmox VM 模板的配置文件。

## 概述

该 Packer 配置从 Ubuntu 24.04 ISO 构建一个预配置的 Proxmox VM 模板，包含：

- **清华大学镜像源**：替换默认的 Ubuntu 镜像源
- **预装软件包**：curl, ca-certificates, git, proxychains4, jq
- **优化的 cloud-init 配置**：使用 Proxmox datasource
- **系统优化**：禁用自动更新，配置 QEMU Guest Agent

## 前置要求

### 1. 本地环境

- **Packer** >= 1.9.0（[安装指南](https://developer.hashicorp.com/packer/downloads)）
- 可访问 Proxmox API 的网络连接

### 2. Proxmox 环境

#### 2.1 上传 Ubuntu ISO

在 Proxmox 节点上执行：

```bash
cd /var/lib/vz/template/iso
wget https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/24.04/ubuntu-24.04-live-server-amd64.iso
```

或通过 Proxmox Web UI 上传 ISO 到 `local` 存储。

#### 2.2 创建 API Token

在 Proxmox Web UI 中：

1. 进入 **Datacenter** → **Permissions** → **API Tokens**
2. 创建新 Token（例如：`terraform@pve!coder`）
3. 记录 Token ID 和 Secret

或使用命令行：

```bash
pveum user token add terraform@pve coder -privsep 0
```

## 快速开始

### 1. 配置环境变量

```bash
cd packer

# 复制环境变量模板
cp .env.example .env

# 编辑 .env 文件，填入实际的 Proxmox API 凭据
nano .env
```

示例 `.env` 内容：

```bash
export PROXMOX_API_URL="https://192.168.1.100:8006/api2/json"
export PROXMOX_API_TOKEN_ID="terraform@pve!coder"
export PROXMOX_API_TOKEN_SECRET="your-actual-token-secret"
```

### 2. 加载环境变量

```bash
source .env
```

### 3. 初始化 Packer

```bash
packer init ubuntu-24.04.pkr.hcl
```

### 4. 验证配置

```bash
packer validate -var-file="config.pkrvars.hcl" ubuntu-24.04.pkr.hcl
```

### 5. 构建模板

```bash
packer build -var-file="config.pkrvars.hcl" ubuntu-24.04.pkr.hcl
```

构建过程预计需要 **15-20 分钟**。

## 文件结构

```
packer/
├── ubuntu-24.04.pkr.hcl       # 主构建配置文件
├── variables.pkr.hcl          # 变量定义
├── config.pkrvars.hcl         # 配置变量（可提交到 git）
├── .env.example               # 环境变量模板
├── .env                       # 实际环境变量（不提交到 git）
├── http/
│   ├── user-data.pkrtpl.hcl   # Ubuntu autoinstall 配置模板
│   └── meta-data              # 空元数据文件
├── scripts/
│   ├── setup.sh               # 系统配置脚本（镜像源、软件包）
│   ├── cleanup.sh             # 清理脚本（准备模板）
│   └── 99-pve.cfg             # Proxmox cloud-init datasource 配置
└── README.md                  # 本文档
```

## 配置说明

### 修改模板配置

编辑 `config.pkrvars.hcl` 文件：

```hcl
# 模板 ID（与 Terraform 的 clone_template_vmid 保持一致）
template_id = 999

# 模板名称
template_name = "ubuntu-2404-coder-template"

# VM 硬件配置
cpu_cores = 2
memory    = 4096
disk_size = "20G"

# 存储配置
storage_pool     = "local-lvm"
iso_storage_pool = "local"
network_bridge   = "vmbr0"
```

### 添加额外软件包

编辑 `scripts/setup.sh`，在软件包安装部分添加：

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    ca-certificates \
    git \
    proxychains4 \
    jq \
    你的新软件包
```

### 修改镜像源

编辑 `scripts/setup.sh`，修改 `/etc/apt/sources.list` 部分。

## 验证模板

### 在 Proxmox 上验证

```bash
# 查看模板配置
qm config 999

# 检查关键配置
qm config 999 | grep -E 'template:|agent:|name:'
```

预期输出：

```
name: ubuntu-2404-coder-template
template: 1
agent: 1
```

### 测试克隆

```bash
# 克隆测试 VM
qm clone 999 100 --name test-coder-vm --full 0

# 配置 cloud-init
qm set 100 --ciuser testuser --cipassword testpass --ipconfig0 ip=dhcp

# 启动 VM
qm start 100

# 等待启动后 SSH 进入
ssh testuser@<vm-ip>

# 验证镜像源
cat /etc/apt/sources.list

# 验证预装软件包
dpkg -l | grep -E 'curl|git|jq|proxychains4'

# 验证启动时间
systemd-analyze

# 清理测试 VM
qm stop 100
qm destroy 100
```

## 与 Terraform 集成

确保 `terraform.tfvars` 中的 `clone_template_vmid` 与 Packer 构建的模板 ID 一致：

```hcl
clone_template_vmid = 999
```

然后正常使用 Terraform：

```bash
cd ..
terraform init
terraform plan
terraform apply
```

## 故障排查

### 1. Packer 无法连接 Proxmox

**问题**：`Error: Failed to connect to Proxmox API`

**解决方案**：

```bash
# 测试 API 连接
curl -k -H "Authorization: PVEAPIToken=${PROXMOX_API_TOKEN_ID}=${PROXMOX_API_TOKEN_SECRET}" \
  ${PROXMOX_API_URL}/version

# 检查环境变量
echo $PROXMOX_API_URL
echo $PROXMOX_API_TOKEN_ID
```

### 2. Boot 命令失败

**问题**：VM 未进入 autoinstall 模式

**解决方案**：

- 增加 `boot_wait` 时间（编辑 `ubuntu-24.04.pkr.hcl`）
- 在 Proxmox Web UI 中查看 VM 控制台输出
- 检查 HTTP 服务器端口 8802 是否被占用

### 3. SSH 连接超时

**问题**：`Timeout waiting for SSH`

**解决方案**：

- 检查网络配置（DHCP 是否正常工作）
- 在 Proxmox UI 中查看 VM 控制台，确认系统已启动
- 增加 `ssh_timeout`（编辑 `config.pkrvars.hcl`）

### 4. Autoinstall 失败

**问题**：Ubuntu 安装过程出错

**解决方案**：

- 在 Proxmox UI 中查看 VM 控制台输出
- 检查 `http/user-data.pkrtpl.hcl` 的 YAML 语法
- 验证 ISO 校验和是否正确

### 5. Cloud-init 在克隆的 VM 上不工作

**问题**：克隆的 VM 无法正确初始化

**解决方案**：

- 确保 `cleanup.sh` 脚本正确执行
- 验证 `/etc/cloud/cloud.cfg.d/99-pve.cfg` 存在
- 检查 machine-id 是否被清空

## 优化建议

### 加速构建

- 使用本地 APT 镜像/缓存
- 启用 APT 并行下载（在 `setup.sh` 中添加）：

  ```bash
  echo 'Acquire::Queue-Mode "host";' | sudo tee /etc/apt/apt.conf.d/99parallel
  ```

### 模板维护

- **定期重建**：每月重建模板以获取安全更新
- **版本化命名**：使用日期标记模板名称，例如 `ubuntu-2404-coder-v20260116`
- **保留历史版本**：保留 2-3 个旧版本以便回滚

### 扩展功能

#### 预装开发环境

编辑 `scripts/setup.sh` 添加：

```bash
# Node.js
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker
```

#### 自定义用户配置

编辑 `http/user-data.pkrtpl.hcl`，在 `late-commands` 中添加：

```yaml
late-commands:
  - curtin in-target --target=/target -- your-custom-command
```

## 构建过程详解

Packer 构建流程：

1. **创建 VM**（VMID 999）
2. **挂载 ISO** 并启动
3. **执行 autoinstall**（约 5-8 分钟）
   - 分区磁盘（LVM）
   - 安装基础系统
   - 创建 packer 用户
4. **SSH Provisioning**（约 5-10 分钟）
   - 等待 cloud-init 完成
   - 执行 `setup.sh`（配置镜像源、安装软件）
   - 上传 `99-pve.cfg`
   - 执行 `cleanup.sh`（清理系统）
5. **转换为模板**

## 预期效果

| 指标 | 原流程 | Packer 方案 |
|------|--------|------------|
| 首次启动时间 | 60-120 秒 | 20-30 秒 |
| 镜像源配置 | 每次启动 | 模板预配置 |
| 软件包安装 | 每次启动 | 模板预装 |
| 自动化程度 | 半自动 | 全自动 |

## 参考资料

- [Ubuntu Autoinstall 文档](https://ubuntu.com/server/docs/install/autoinstall)
- [Packer Proxmox Builder](https://www.packer.io/plugins/builders/proxmox/iso)
- [Building Ubuntu Server 24.04 Templates for Proxmox with Packer](https://thecomalley.github.io/packer-proxmox-ubuntu)

## 许可证

与父项目相同。
