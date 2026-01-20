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
    net-tools 、    
    jq \
    wget \
    apt-transport-https \
    gnupg \
    software-properties-common

echo "✓ Required packages installed"

# ============================================
# 4. 安装 Node.js（NodeSource APT）
# ============================================
echo ""
echo "==> Installing Node.js via NodeSource APT..."

if curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -; then
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs; then
        node -v
        npm -v
        echo "✓ Node.js installed via NodeSource APT"
        
        # 配置 npm 镜像源
        echo ""
        echo "==> Configuring npm registry mirror..."
        sudo npm config set registry https://registry.npmmirror.com
        echo "✓ npm registry configured"
        
        # 安装全局 npm 包
        echo ""
        echo "==> Installing global npm packages..."
        sudo npm install -g opencode-ai
        sudo npm install -g @anthropic-ai/claude-code
        sudo npm install -g @google/gemini-cli
        sudo npm install -g @openai/codex
        echo "✓ Global npm packages installed"
    else
        echo "⚠️ Node.js install skipped (apt failure)"
    fi
else
    echo "⚠️ Node.js install skipped (network failure)"
fi

# ============================================
# 5. 安装 Go（官方发行版）
# ============================================
echo ""
echo "==> Installing Go from official tarball..."

GO_VERSION="1.24.12"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://mirrors.aliyun.com/golang/${GO_TARBALL}"

if curl -fsSL "${GO_URL}" -o "/tmp/${GO_TARBALL}"; then
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
    sudo tee /etc/profile.d/go.sh > /dev/null <<'EOF'
export PATH="/usr/local/go/bin:${PATH}"
EOF
    export PATH="/usr/local/go/bin:${PATH}"
    go version
    echo "✓ Go installed from official tarball"
else
    echo "⚠️ Go install skipped (download failure)"
fi

# ============================================
# 6. 禁用自动更新（模板中不需要）
# ============================================
echo ""
echo "==> Disabling automatic updates..."

sudo systemctl disable apt-daily.timer 2>/dev/null || true
sudo systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
sudo systemctl mask apt-daily.service 2>/dev/null || true
sudo systemctl mask apt-daily-upgrade.service 2>/dev/null || true

echo "✓ Automatic updates disabled"

# ============================================
# 7. 确保 qemu-guest-agent 已启用
# ============================================
echo ""
echo "==> Ensuring qemu-guest-agent is enabled..."

sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent

echo "✓ QEMU Guest Agent enabled"

# ============================================
# 8. 配置 cloud-init
# ============================================
echo ""
echo "==> Configuring cloud-init datasource priority..."

sudo tee /etc/cloud/cloud.cfg.d/90_dpkg.cfg > /dev/null <<'EOF'
# 优先使用 ConfigDrive 和 NoCloud 数据源
datasource_list: [ ConfigDrive, NoCloud, None ]
EOF

echo "✓ Cloud-init configured"

# ============================================
# 9. 禁用 cloud-init 网络等待超时
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
# 10. 写入模板构建时间
# ============================================
echo ""
echo "==> Writing template build metadata..."

BUILD_TIME_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
sudo tee /etc/template-build-info > /dev/null <<EOF
TEMPLATE_BUILD_TIME_UTC=${BUILD_TIME_UTC}
EOF

echo "✓ Template build metadata written: ${BUILD_TIME_UTC}"

# ============================================
# 完成
# ============================================
echo ""
echo "============================================"
echo "System setup completed successfully!"
echo "============================================"
