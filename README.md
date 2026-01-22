---

# Proxmox VM Coder 模板

在 Proxmox 上配置 Linux 虚拟机作为 [Coder 工作空间](https://coder.com/docs/workspaces)。该模板克隆一个 cloud‑init 基础镜像，通过 Snippets 注入 user‑data，并在工作空间所有者的 Linux 用户下运行 Coder 代理。

## 前置要求

- Proxmox VE 8/9
- 具有访问节点和存储权限的 Proxmox API 令牌
- 从 Coder 配置器到 Proxmox VE 的 SSH 访问
- 启用了 "Snippets" 内容的存储
- Proxmox 上的 Ubuntu cloud‑init 镜像/模板
  - 最新镜像：https://cloud-images.ubuntu.com/ ([源](https://cloud-images.ubuntu.com/))

## 准备 Proxmox Cloud‑Init 模板（一次性操作）

在 Proxmox 节点上运行。使用 RELEASE 变量以便始终拉取最新镜像。

```bash
# 选择一个发行版（例如 jammy 或 noble）
RELEASE=noble
IMG_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/${RELEASE}/current/${RELEASE}-server-cloudimg-amd64.img"
IMG_PATH="/var/lib/vz/template/iso/${RELEASE}-server-cloudimg-amd64.img"

# 下载云镜像（优先使用缓存）
if [ -f "$IMG_PATH" ] && [ -s "$IMG_PATH" ]; then
  echo "Using cached image: $IMG_PATH"
else
  wget "$IMG_URL" -O "$IMG_PATH"
fi

# 创建基础虚拟机（示例 ID 999），启用 QGA，修正启动顺序
NAME="ubuntu-${RELEASE}-cloudinit"
qm create 999 --name "$NAME" --memory 4096 --cores 2 \
  --net0 virtio,bridge=vmbr0 --agent enabled=1
qm set 999 --scsihw virtio-scsi-pci
qm importdisk 999 "$IMG_PATH" local-lvm
qm set 999 --scsi0 local-lvm:vm-999-disk-0
qm set 999 --ide2 local-lvm:cloudinit
qm set 999 --serial0 socket --vga serial0
qm set 999 --boot 'order=scsi0;ide2;net0'
```

### （可选）在模板中预装 Node.js 等 SDK

建议在模板构建阶段完成安装，以减少工作空间首次启动时间。可选两种常见方式：

- **NodeSource APT**（固定版本、简单）
- **nvm**（按用户安装、易切换版本）

示例（NodeSource，固定 LTS 版本）：

```bash
# 先启动模板 VM 并进入（或用 cloud-init/packer 构建时执行）
sudo apt-get update
sudo apt-get install -y curl ca-certificates gnupg build-essential git python3
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node -v && npm -v

# 清理，减少模板体积
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
```

建议：
- 固定 Node.js 主版本（如 20.x/22.x），避免模板不稳定。
- 若使用 nvm，考虑放到 `/etc/profile.d/` 并为默认用户设置 `nvm alias default`。
- 定期重建模板以更新安全补丁与 SDK 版本。

验证：

```bash
qm config 999 | grep -E 'template:|agent:|boot:|ide2:|scsi0:'
```

### 通过 GUI 启用 Snippets

- 数据中心 → 存储 → 选择 `local` → 编辑 → 内容 → 勾选 "Snippets" → 确定
- 确保节点上存在 `/var/lib/vz/snippets/` 目录用于存储 snippet 文件
- 模板页面 → Cloud‑Init → Snippet 存储：`local` → 文件：你的 yml → 应用

## 配置此模板

使用你的环境信息编辑 `terraform.tfvars`：

```hcl
# Proxmox API
proxmox_api_url          = "https://192.168.1.100:8006/api2/json"
proxmox_api_token_id     = "terraform@pve!coder"
proxmox_api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# SSH 到节点（用于上传 snippet）
proxmox_host     = "192.168.1.100"
proxmox_password = "your-root-password"
proxmox_ssh_user = "root"

# 基础设施默认值
proxmox_node        = "pve"
disk_storage        = "local-lvm"
snippet_storage     = "local"
bridge              = "vmbr0"
vlan                = 0
clone_template_vmid = 999
```

### 变量（terraform.tfvars）

- 这些值是模板在应用时读取的标准 Terraform 变量。
- 将机密信息（例如 `proxmox_api_token_secret`、`proxmox_password`）放在 `terraform.tfvars` 中，或使用 `TF_VAR_*` 环境变量注入（例如 `TF_VAR_proxmox_api_token_secret`）。
- 如果直接运行 Terraform，也可以使用 `-var`/`-var-file` 覆盖。使用 Coder 时，推送模板时会打包仓库的 `terraform.tfvars`。

预期的变量：

- `proxmox_api_url`、`proxmox_api_token_id`、`proxmox_api_token_secret`（敏感信息）
- `proxmox_host`、`proxmox_password`（敏感信息）、`proxmox_ssh_user`
- `proxmox_node`、`disk_storage`、`snippet_storage`、`bridge`、`vlan`、`clone_template_vmid`
- Coder 参数：`cpu_cores`、`memory_mb`、`disk_size_gb`

## Proxmox API 令牌（GUI/CLI）

文档：https://pve.proxmox.com/wiki/User_Management#pveum_tokens

GUI：

1. （可选）创建自动化用户：数据中心 → 权限 → 用户 → 添加（例如 `terraform@pve`）
2. 权限：数据中心 → 权限 → 添加 → 用户权限
   - 路径：`/`（或更窄的路径覆盖你的节点/存储）
   - 角色：`PVEVMAdmin` + `PVEStorageAdmin`（或简单起见使用 `PVEAdmin`）
3. 令牌：数据中心 → 权限 → API 令牌 → 添加 → 复制令牌 ID 和密钥
4. 测试：

```bash
curl -k -H "Authorization: PVEAPIToken=<USER@REALM>!<TOKEN>=<SECRET>" \
  https:// < PVE_HOST > :8006/api2/json/version
```

CLI：

```bash
pveum user add terraform@pve --comment 'Terraform 自动化用户'
pveum aclmod / -user terraform@pve -role PVEAdmin
pveum user token add terraform@pve terraform --privsep 0
```

## 使用

### 预缓存 VS Code（推荐）

为了加速 VS Code 启动并避免网络下载阻塞，建议预先缓存 VS Code：

```bash
# 缓存 VS Code Server（用于 VS Code Desktop 远程连接）
sudo ./cache-vscode-server.sh

# 缓存 VS Code Web（用于浏览器访问）
sudo ./cache-vscode.sh
```

这将把 VS Code 下载到 NFS share (`/share/vscode-cache/`)，新建的 workspace 会自动使用缓存。

**解决 VS Code Desktop 下载阻塞问题：**
- VS Code Desktop 通过 SSH 连接时需要在远程主机下载 VS Code Server
- 如果网络不稳定或有代理/路由切换，可能导致下载阻塞
- 预缓存可以完全避免从互联网下载，实现秒开

### 路由切换说明

workspace 启动后默认使用主路由。如需切换到旁路由：

```bash
# 切换到旁路由（用于科学上网等）
sudo /usr/local/sbin/route-switch.sh to-bypass

# 切换回主路由
sudo /usr/local/sbin/route-switch.sh to-main

# 查看当前路由状态
sudo /usr/local/sbin/route-switch.sh status
```

> ⚠️ **注意**：启动脚本中不再自动切换路由，避免阻塞 VS Code Server 下载。等 workspace 完全启动后再根据需要手动切换。

### 部署 workspace

```bash
# 在此目录下执行
coder templates push --yes proxmox-cloudinit --directory . | cat
```

在 Coder UI 中从此模板创建工作空间。首次启动通常需要 60–120 秒以运行 cloud‑init。

## 旁路由切换脚本

模板会在工作空间中安装路由切换脚本：`/usr/local/sbin/route-switch.sh`。可通过环境变量覆盖默认网关、DNS、网卡等参数。

示例：

```bash
sudo /usr/local/sbin/route-switch.sh status
sudo /usr/local/sbin/route-switch.sh to-bypass
sudo /usr/local/sbin/route-switch.sh to-main
```

## Terraform Init 加速方案配置

当遇到 `terraform init` 因网络延迟导致 Provider 下载超时，可配置阿里云镜像站加速。Terraform CLI 自 0.13.2 起支持网络镜像。

创建 Terraform CLI 配置文件：

- Windows：`terraform.rc` 放在 `%APPDATA%` 目录（PowerShell 用 `$env:APPDATA` 查看）
- 其他系统：`~/.terraformrc`（或通过 `TF_CLI_CONFIG_FILE` 指定，文件名需匹配 `*.tfrc`）

示例（macOS/Linux）：

```hcl
provider_installation {
  network_mirror {
    url = "https://mirrors.aliyun.com/terraform/"
    # 仅将阿里云相关 Provider 走国内镜像
    include = [
      "registry.terraform.io/aliyun/alicloud",
      "registry.terraform.io/hashicorp/alicloud",
    ]
  }
  direct {
    # 其他 Provider 保持默认下载链路
    exclude = [
      "registry.terraform.io/aliyun/alicloud",
      "registry.terraform.io/hashicorp/alicloud",
    ]
  }
}
```

验证：在 Terraform 模板目录执行 `terraform init`，若初始化成功并正常下载 Provider，则配置生效。

## 工作原理

- 通过提供商的 `proxmox_virtual_environment_file` 将渲染后的 cloud‑init user‑data 上传到 `<storage>:snippets/<vm>.yml`
- 虚拟机配置：`virtio-scsi-pci`，启动顺序 `scsi0, ide2, net0`，启用 QGA
- Linux 用户等于 Coder 工作空间所有者（经过清理）。为避免冲突，保留名称（`admin`、`root` 等）会添加后缀（例如 `admin1`）。用户创建时使用 `primary_group: adm`、`groups: [sudo]`、`no_user_group: true`
- systemd 服务以该用户身份运行：
  - `coder-agent.service`

## 故障排查要点

- iPXE 启动循环：确保模板有可启动的根磁盘，启动顺序为 `scsi0,ide2,net0`
- QGA 无响应：在模板中安装/启用 QGA；首次启动时等待 60–120 秒
- Snippet 上传错误：存储必须包含 `Snippets`；令牌需要数据存储权限；路径格式 `<storage>:snippets/<file>` 由提供商处理
- 权限错误：确保令牌的角色覆盖目标节点和存储
- 验证 snippet/QGA：`qm config <vmid> | egrep 'cicustom|ide2|ciuser'`
- systemd-networkd-wait-online 卡住（start running 38s/no limit）：
  - 检查是否使用了 cloud-init 正确配置网络（Netplan/Cloud-Init）。
  - 若仅为等待超时，可临时降低/禁用等待：  
    `sudo systemctl disable systemd-networkd-wait-online.service`  
    或 `sudo systemctl edit systemd-networkd-wait-online.service` 设置 `TimeoutStartSec=10s`。
- 网络需使用 DHCP（cloud-init/Netplan），确保获取地址后网络在线。

## 参考资料

- Ubuntu 云镜像（最新）：https://cloud-images.ubuntu.com/ ([源](https://cloud-images.ubuntu.com/))
- Proxmox qm(1) 手册：https://pve.proxmox.com/pve-docs/qm.1.html
- Proxmox Cloud‑Init 支持：https://pve.proxmox.com/wiki/Cloud-Init_Support
- Terraform Proxmox 提供商（bpg）：Terraform Registry 上的 `bpg/proxmox`
- Coder – 最佳实践与模板：
  - https://coder.com/docs/tutorials/best-practices/speed-up-templates
  - https://coder.com/docs/tutorials/template-from-scratch
