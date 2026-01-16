#!/bin/bash
# Packer 系统配置脚本
# 用于配置 Ubuntu 24.04 系统：替换镜像源、安装软件包

set -e

echo "============================================"
echo "Starting system setup..."
echo "============================================"

# ============================================
# 1. 配置清华大学镜像源
# ============================================
echo ""
echo "==> Configuring Tsinghua University Ubuntu mirrors..."

sudo tee /etc/apt/sources.list > /dev/null <<'EOF'
# 清华大学开源软件镜像站 - Ubuntu 24.04 (Noble)
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ noble-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ noble-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ noble-security main restricted universe multiverse
EOF

echo "✓ Mirror sources configured"

# ============================================
# 2. 更新包索引
# ============================================
echo ""
echo "==> Updating package index..."

sudo apt-get update

echo "✓ Package index updated"

# ============================================
# 3. 安装必需的软件包
# ============================================
echo ""
echo "==> Installing required packages..."

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    ca-certificates \
    git \
    proxychains4 \
    jq \
    wget \
    apt-transport-https \
    gnupg \
    software-properties-common

echo "✓ Required packages installed"

# ============================================
# 4. 配置 proxychains4
# ============================================
echo ""
echo "==> Configuring proxychains4..."

sudo tee /etc/proxychains4.conf > /dev/null <<'EOF'
# Proxychains 配置文件
# 用户可以后续根据需要修改代理设置

strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
# 添加你的代理服务器配置
# 示例（取消注释并修改）:
# socks5 127.0.0.1 1080
# socks4 127.0.0.1 1080
# http  127.0.0.1 8080
EOF

echo "✓ Proxychains4 configured"

# ============================================
# 5. 禁用自动更新（模板中不需要）
# ============================================
echo ""
echo "==> Disabling automatic updates..."

sudo systemctl disable apt-daily.timer 2>/dev/null || true
sudo systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
sudo systemctl mask apt-daily.service 2>/dev/null || true
sudo systemctl mask apt-daily-upgrade.service 2>/dev/null || true

echo "✓ Automatic updates disabled"

# ============================================
# 6. 确保 qemu-guest-agent 已启用
# ============================================
echo ""
echo "==> Ensuring qemu-guest-agent is enabled..."

sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent

echo "✓ QEMU Guest Agent enabled"

# ============================================
# 7. 配置 cloud-init
# ============================================
echo ""
echo "==> Configuring cloud-init datasource priority..."

sudo tee /etc/cloud/cloud.cfg.d/90_dpkg.cfg > /dev/null <<'EOF'
# 优先使用 ConfigDrive 和 NoCloud 数据源
datasource_list: [ ConfigDrive, NoCloud, None ]
EOF

echo "✓ Cloud-init configured"

# ============================================
# 8. 禁用 cloud-init 网络等待超时
# ============================================
echo ""
echo "==> Configuring systemd network wait timeout..."

sudo mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d

sudo tee /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf > /dev/null <<'EOF'
[Service]
TimeoutStartSec=10s
EOF

echo "✓ Network wait timeout configured"

# ============================================
# 完成
# ============================================
echo ""
echo "============================================"
echo "System setup completed successfully!"
echo "============================================"
