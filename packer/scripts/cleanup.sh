#!/bin/bash
# Packer 清理脚本
# 用于清理系统，确保模板可以被正确克隆

set -e

echo "============================================"
echo "Starting system cleanup..."
echo "============================================"

# ============================================
# 1. 停止服务
# ============================================
echo ""
echo "==> Stopping services..."

sudo systemctl stop qemu-guest-agent || true

echo "✓ Services stopped"

# ============================================
# 2. 清理 APT 缓存
# ============================================
echo ""
echo "==> Cleaning APT cache..."

sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get clean -y
sudo rm -rf /var/lib/apt/lists/*

echo "✓ APT cache cleaned"

# ============================================
# 3. 清理日志
# ============================================
echo ""
echo "==> Cleaning logs..."

sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
sudo find /var/log -type f -name "*.gz" -delete
sudo find /var/log -type f -name "*.1" -delete
sudo find /var/log -type f -name "*.old" -delete
sudo journalctl --vacuum-time=1s

echo "✓ Logs cleaned"

# ============================================
# 4. 清理临时文件
# ============================================
echo ""
echo "==> Cleaning temporary files..."

sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

echo "✓ Temporary files cleaned"

# ============================================
# 5. 删除 SSH 主机密钥（重要！）
# ============================================
echo ""
echo "==> Removing SSH host keys..."

sudo rm -f /etc/ssh/ssh_host_*

echo "✓ SSH host keys removed"

# ============================================
# 6. 清空 machine-id（重要！）
# ============================================
echo ""
echo "==> Truncating machine-id..."

sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "✓ Machine-id truncated"

# ============================================
# 7. 删除特定的 cloud-init 配置文件
# ============================================
echo ""
echo "==> Removing specific cloud-init configuration files..."

# 这些文件会干扰 Proxmox 的 cloud-init 配置
sudo rm -f /etc/cloud/cloud.cfg.d/50-curtin-networking.cfg
sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
sudo rm -f /etc/cloud/cloud.cfg.d/90-installer-network.cfg
sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
sudo rm -f /etc/cloud/cloud-init.disabled
sudo rm -f /etc/netplan/50-cloud-init.yaml

echo "✓ Specific cloud-init files removed"

# ============================================
# 8. 清理 cloud-init 状态（重要！）
# ============================================
echo ""
echo "==> Cleaning cloud-init state..."

sudo cloud-init clean --logs --seed

echo "✓ Cloud-init state cleaned"

# ============================================
# 9. 清理 shell 历史记录
# ============================================
echo ""
echo "==> Cleaning shell history..."

history -c
cat /dev/null > ~/.bash_history
sudo sh -c ': > /root/.bash_history' 2>/dev/null || true

echo "✓ Shell history cleaned"

# ============================================
# 10. 清理网络配置
# ============================================
echo ""
echo "==> Cleaning network configuration..."

sudo rm -f /etc/netplan/00-installer-config.yaml

echo "✓ Network configuration cleaned"

# ============================================
# 11. 清理用户缓存和配置
# ============================================
echo ""
echo "==> Cleaning user cache..."

sudo rm -rf ~/.cache/*
sudo rm -rf ~/.config/*

echo "✓ User cache cleaned"

# ============================================
# 12. 同步文件系统
# ============================================
echo ""
echo "==> Syncing filesystem..."

sync

echo "✓ Filesystem synced"

# ============================================
# 完成
# ============================================
echo ""
echo "============================================"
echo "Cleanup completed successfully!"
echo "System is ready to be converted to template"
echo "============================================"
