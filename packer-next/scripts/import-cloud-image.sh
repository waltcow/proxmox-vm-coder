#!/bin/bash
# 导入 Ubuntu 24.04 Cloud Image 到 Proxmox
# 使用前请确保已设置环境变量或修改以下配置

set -e

# ============================================
# 配置
# ============================================
VMID="${VMID:-9000}"
VM_NAME="${VM_NAME:-ubuntu-2404-cloud-base}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"

# Cloud Image URL
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
# 备用镜像（清华源）
CLOUD_IMAGE_URL_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/noble/current/noble-server-cloudimg-amd64.img"

# SHA256SUMS URL
SHA256SUMS_URL="https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"

# 使用 Proxmox 默认的模板目录
DOWNLOAD_DIR="/var/lib/vz/template/iso"
IMAGE_NAME="noble-server-cloudimg-amd64.img"
SHA256_FILE="SHA256SUMS"

echo "============================================"
echo "Ubuntu 24.04 Cloud Image 导入工具"
echo "============================================"
echo ""
echo "配置："
echo "  VMID:    ${VMID}"
echo "  VM名称:  ${VM_NAME}"
echo "  存储池:  ${STORAGE}"
echo "  网桥:    ${BRIDGE}"
echo ""

# ============================================
# 检查是否在 Proxmox 节点上运行
# ============================================
if ! command -v qm &> /dev/null; then
    echo "错误: 此脚本需要在 Proxmox 节点上运行"
    exit 1
fi

# ============================================
# 检查 VM 是否已存在
# ============================================
if qm status "${VMID}" &> /dev/null; then
    echo "警告: VM ${VMID} 已存在, 是否删除并重新创建[y/N]"
    
    # 检查是否为模板
    if qm config "${VMID}" | grep -q "^template: 1"; then
        echo "VM ${VMID} 是一个模板"
    fi
    
    # 检查 VM 状态
    VM_STATUS=$(qm status "${VMID}" | awk '{print $2}')
    echo "当前状态: ${VM_STATUS}"
    
    read -p "是否删除并重新创建? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "==> 删除现有 VM ${VMID}..."
        
        # 如果 VM 正在运行，先停止
        if [[ "${VM_STATUS}" == "running" ]]; then
            echo "正在停止 VM ${VMID}..."
            qm stop "${VMID}"
            sleep 3
        fi
        
        # 如果是模板，先转换回 VM 再删除
        if qm config "${VMID}" | grep -q "^template: 1"; then
            echo "正在将模板转换回 VM..."
            qm template "${VMID}" --revert 2>/dev/null || true
            sleep 1
        fi
        
        # 删除 VM
        qm destroy "${VMID}" --purge || {
            echo "错误: 删除 VM 失败"
            exit 1
        }
        
        echo "✓ VM ${VMID} 已删除"
        sleep 2
    else
        echo "取消操作"
        exit 0
    fi
fi

# ============================================
# 下载 Cloud Image
# ============================================
echo ""
echo "==> 下载 Cloud Image..."

# 确保下载目录存在
mkdir -p "${DOWNLOAD_DIR}"
cd "${DOWNLOAD_DIR}"

# 检查是否已有完整的镜像
if [ -f "${IMAGE_NAME}" ]; then
    echo "发现已存在的镜像文件: ${DOWNLOAD_DIR}/${IMAGE_NAME}"
    read -p "是否验证并重用? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        REUSE_IMAGE=1
    else
        echo "删除旧镜像，准备重新下载..."
        rm -f "${IMAGE_NAME}"
    fi
fi

# 下载或验证镜像
if [ -z "${REUSE_IMAGE}" ]; then
    # 下载校验和文件
    echo "下载校验和文件..."
    if ! wget -q --show-progress "${SHA256SUMS_URL}" -O "${SHA256_FILE}"; then
        echo "警告: 无法下载校验和文件，将跳过验证"
        SKIP_VERIFY=1
    fi

    # 下载镜像
    echo "尝试从清华镜像下载..."
    if ! wget -q --show-progress "${CLOUD_IMAGE_URL_MIRROR}" -O "${IMAGE_NAME}"; then
        echo "清华镜像下载失败,尝试官方源..."
        if ! wget -q --show-progress "${CLOUD_IMAGE_URL}" -O "${IMAGE_NAME}"; then
            echo "错误: 无法下载 Cloud Image"
            exit 1
        fi
    fi
else
    # 重用现有镜像，仍需下载校验和文件以验证
    echo "下载校验和文件以验证现有镜像..."
    if ! wget -q --show-progress "${SHA256SUMS_URL}" -O "${SHA256_FILE}"; then
        echo "警告: 无法下载校验和文件，将跳过验证"
        SKIP_VERIFY=1
    fi
fi

# 验证下载的文件
if [ -z "${SKIP_VERIFY}" ] && [ -f "${SHA256_FILE}" ]; then
    echo ""
    echo "==> 验证镜像完整性..."
    if grep "${IMAGE_NAME}" "${SHA256_FILE}" | sha256sum -c --status; then
        echo "✓ 镜像校验通过"
    else
        echo "错误: 镜像校验失败，文件可能已损坏"
        echo "请删除 ${DOWNLOAD_DIR}/${IMAGE_NAME} 后重试"
        exit 1
    fi
else
    echo "⚠️ 跳过镜像校验"
fi

echo "✓ Cloud Image 准备完成"

# ============================================
# 创建 VM
# ============================================
echo ""
echo "==> 创建 VM ${VMID}..."

qm create "${VMID}" \
    --name "${VM_NAME}" \
    --memory 2048 \
    --cores 2 \
    --net0 "virtio,bridge=${BRIDGE}"

echo "✓ VM 创建完成"

# ============================================
# 导入磁盘
# ============================================
echo ""
echo "==> 导入 Cloud Image 磁盘..."

if ! qm importdisk "${VMID}" "${DOWNLOAD_DIR}/${IMAGE_NAME}" "${STORAGE}"; then
    echo "错误: 磁盘导入失败"
    echo "正在清理..."
    qm destroy "${VMID}" --purge || true
    echo ""
    echo "建议："
    echo "  1. 删除损坏的镜像: rm ${DOWNLOAD_DIR}/${IMAGE_NAME}"
    echo "  2. 检查存储空间: pvs && vgs && lvs"
    echo "  3. 重新运行此脚本"
    exit 1
fi

echo "✓ 磁盘导入完成"

# ============================================
# 配置 VM
# ============================================
echo ""
echo "==> 配置 VM..."

# 配置 SCSI 控制器和磁盘
qm set "${VMID}" --scsihw virtio-scsi-pci --scsi0 "${STORAGE}:vm-${VMID}-disk-0"

# 添加 Cloud-Init 驱动器
qm set "${VMID}" --ide2 "${STORAGE}:cloudinit"

# 配置启动顺序
qm set "${VMID}" --boot c --bootdisk scsi0

# 配置串口（cloud-init 需要）
qm set "${VMID}" --serial0 socket --vga serial0

# 启用 QEMU Guest Agent
qm set "${VMID}" --agent enabled=1

# 配置 Cloud-Init 默认用户和 SSH 密钥
echo ""
echo "==> 配置 Cloud-Init..."

# 创建自定义 cloud-init vendor 配置文件（配置清华源）
VENDOR_FILE="/var/lib/vz/snippets/vendor-tuna.yaml"
cat > "${VENDOR_FILE}" <<'EOF'
#cloud-config
apt:
  primary:
    - arches: [default]
      uri: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
  security:
    - arches: [default]
      uri: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
package_upgrade: false
package_reboot_if_required: false
EOF

echo "✓ 创建了 cloud-init vendor 配置文件"

# 设置默认用户
qm set "${VMID}" --ciuser ubuntu

# 如果存在 SSH 公钥，自动配置
SSH_PUB_KEY="${HOME}/.ssh/id_rsa.pub"
if [ -f "${SSH_PUB_KEY}" ]; then
    echo "发现 SSH 公钥，自动配置..."
    qm set "${VMID}" --sshkeys "${SSH_PUB_KEY}"
    echo "✓ SSH 密钥已配置"
else
    echo "警告: 未找到 ${SSH_PUB_KEY}"
    echo "请手动配置 SSH 密钥: qm set ${VMID} --sshkeys /path/to/your/key.pub"
fi

# 应用自定义 vendor 配置
qm set "${VMID}" --cicustom "vendor=local:snippets/vendor-tuna.yaml"
echo "✓ 已应用清华源配置（cloud-init 会自动使用）"

# 配置固定 IP（用于 Packer 构建）
# 克隆后的 VM 会继承此配置
qm set "${VMID}" --ipconfig0 ip=192.168.50.250/24,gw=192.168.50.254

echo "✓ VM 配置完成（使用固定 IP: 192.168.50.250）"

# ============================================
# 扩展磁盘（可选）
# ============================================
echo ""
echo "==> 扩展磁盘到 20G..."

qm resize "${VMID}" scsi0 20G

echo "✓ 磁盘扩展完成"

# ============================================
# 启动 VM 并安装 qemu-guest-agent
# ============================================
echo ""
echo "==> 启动 VM 安装 qemu-guest-agent..."

# 启动 VM
qm start "${VMID}"

# 等待 cloud-init 完成和网络就绪
# 使用固定 IP 192.168.50.250
VM_IP="192.168.50.250"

echo "等待 VM 启动和网络就绪（最多 3 分钟）..."
echo "使用固定 IP: ${VM_IP}"

for i in {1..36}; do
    sleep 5
    # 简单 ping 测试，不触发 cloud-init 下载
    if ping -c 1 -W 2 "${VM_IP}" >/dev/null 2>&1; then
        echo "✓ VM 网络已就绪 (${i}次尝试)"
        break
    fi
    echo "等待网络... (${i}/36)"
done

# 额外等待 cloud-init 完成
echo "等待 cloud-init 完成..."

# 等待 cloud-init 真正完成（检查状态）
for i in {1..30}; do
    CLOUD_INIT_STATUS=$(timeout 5 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "${HOME}/.ssh/id_rsa" ubuntu@"${VM_IP}" \
        "cloud-init status" 2>/dev/null | grep -oP 'status: \K\w+' || echo "")
    
    if [ "$CLOUD_INIT_STATUS" = "done" ]; then
        echo "✓ Cloud-init 已完成"
        break
    elif [ "$CLOUD_INIT_STATUS" = "running" ]; then
        echo "等待 cloud-init... (${i}/30) - status: running"
    else
        echo "等待 cloud-init... (${i}/30)"
    fi
    sleep 5
done

# 额外等待 apt 锁释放
echo "等待 apt 锁释放..."
for i in {1..10}; do
    if timeout 5 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "${HOME}/.ssh/id_rsa" ubuntu@"${VM_IP}" \
        "sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1" 2>/dev/null; then
        echo "apt 进程仍在运行，等待... (${i}/10)"
        sleep 3
    else
        echo "✓ apt 锁已释放"
        break
    fi
done

echo "VM IP: ${VM_IP}"
echo ""
echo "==> 安装 qemu-guest-agent..."

# 清华源已在 cloud-init 时配置，直接安装
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "${HOME}/.ssh/id_rsa" ubuntu@"${VM_IP}" \
    "sudo apt-get update && sudo apt-get install -y qemu-guest-agent && sudo systemctl enable qemu-guest-agent && sudo systemctl start qemu-guest-agent"

echo "✓ qemu-guest-agent 安装完成"

# 关闭 VM
echo ""
echo "==> 关闭 VM..."
qm shutdown "${VMID}"
sleep 10

# 等待 VM 完全停止
for i in {1..30}; do
    if qm status "${VMID}" | grep -q "stopped"; then
        echo "✓ VM 已停止"
        break
    fi
    sleep 2
done

# ============================================
# 转换为模板
# ============================================
echo ""
echo "==> 转换为模板..."

qm template "${VMID}"

echo "✓ 模板创建完成"

# ============================================
# 完成
# ============================================
echo ""
echo "============================================"
echo "Cloud Image 导入完成!"
echo "============================================"
echo ""
echo "模板信息："
echo "  VMID:   ${VMID}"
echo "  名称:   ${VM_NAME}"
echo "  用户:   ubuntu"
echo "  SSH:    使用密钥认证"
echo ""
echo "下一步："
echo "  1. 确保你的 SSH 私钥可用: ~/.ssh/id_rsa"
echo "  2. 运行 Packer 构建最终模板:"
echo "     cd packer-next && packer build -var-file=\"config.pkrvars.hcl\" ."
echo ""
