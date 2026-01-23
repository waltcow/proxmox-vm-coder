#!/bin/bash
# Packer 系统配置脚本
# 用于配置 Ubuntu 24.04 系统：替换镜像源、安装软件包

set -e

echo "============================================"
echo "Starting system setup..."
echo "============================================"

# ============================================
# 0. 切换到旁路由（确保能访问外网下载软件）
# ============================================
echo ""
echo "==> Switching to bypass router for external network access..."

if [ -f "/tmp/scripts/route-switch.sh" ]; then
    sudo chmod +x /tmp/scripts/route-switch.sh
    sudo /tmp/scripts/route-switch.sh to-bypass || echo "⚠️ Route switch failed, continuing anyway..."
else
    echo "⚠️ route-switch.sh not found, skipping route switch"
fi

# ============================================
# 1. 配置清华大学镜像源
# ============================================
echo ""
echo "==> Configuring Tsinghua University Ubuntu mirrors..."

# Disable default ubuntu.sources to avoid duplicate entries with /etc/apt/sources.list
if [ -f "/etc/apt/sources.list.d/ubuntu.sources" ]; then
    sudo mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.disabled
fi

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
    net-tools \
    jq \
    wget \
    apt-transport-https \
    gnupg \
    software-properties-common \
    nfs-common

echo "✓ Required packages installed"

# ============================================
# 3.5. 尝试挂载 NFS 共享（用于本地预置包）
# ============================================
echo ""
echo "==> Attempting to mount NFS share for local packages..."

if [ -f "/tmp/scripts/mount-nfs-share.sh" ]; then
    sudo chmod +x /tmp/scripts/mount-nfs-share.sh
    if sudo /tmp/scripts/mount-nfs-share.sh; then
        echo "✓ NFS share mounted"
    else
        echo "⚠️ NFS mount failed, falling back to remote downloads"
    fi
else
    echo "⚠️ mount-nfs-share.sh not found in /tmp/scripts/"
fi

# ============================================
# 4. 安装 Node.js（NodeSource APT）
# ============================================
echo ""
echo "==> Installing Node.js via NodeSource APT..."

NODE_TARBALL=""
if [ -d "/share/nodejs" ]; then
    NODE_TARBALL=$(ls -1 /share/nodejs/node-v*-linux-x64.tar.xz 2>/dev/null | sort -V | tail -n1 || true)
fi

if [ -n "$NODE_TARBALL" ]; then
    echo "==> Installing Node.js from local tarball: $NODE_TARBALL"
    sudo rm -rf /usr/local/node
    sudo mkdir -p /usr/local/node
    sudo tar -xJf "$NODE_TARBALL" -C /usr/local/node --strip-components=1
    sudo tee /etc/profile.d/node.sh > /dev/null <<'EOF'
export PATH="/usr/local/node/bin:${PATH}"
EOF
    # 创建符号链接到 /usr/local/bin，让 sudo 也能找到命令
    sudo ln -sf /usr/local/node/bin/node /usr/local/bin/node
    sudo ln -sf /usr/local/node/bin/npm /usr/local/bin/npm
    sudo ln -sf /usr/local/node/bin/npx /usr/local/bin/npx
    export PATH="/usr/local/node/bin:${PATH}"
    node -v
    npm -v
    echo "✓ Node.js installed from local tarball"
else
    # 手动配置 NodeSource 仓库（避免 setup 脚本的 apt 警告）
    echo "==> Adding NodeSource repository manually..."
    if curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; then
        echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
        sudo apt-get update
        if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs; then
            node -v
            npm -v
            echo "✓ Node.js installed via NodeSource APT"
        else
            echo "⚠️ Node.js install skipped (apt failure)"
        fi
    else
        echo "⚠️ Node.js install skipped (GPG key download failure)"
    fi
fi

# 安装 pnpm
echo ""
echo "==> Installing pnpm..."
sudo npm install -g pnpm@latest-10
pnpm -v
echo "✓ pnpm installed"

# 配置 npm 淘宝镜像源
echo ""
echo "==> Configuring npm registry to npmmirror.com..."
npm config set registry https://registry.npmmirror.com
echo "✓ npm registry configured"

# 安装全局 npm 包
echo ""
echo "==> Installing global npm packages..."
# sudo npm install -g @anthropic-ai/claude-code --registry=https://registry.npmmirror.com
# sudo npm install -g @google/gemini-cli --registry=https://registry.npmmirror.com
# sudo npm install -g @openai/codex --registry=https://registry.npmmirror.com
echo "✓ Global npm packages installed"

# ============================================
# 5. 安装 Go（官方发行版）
# ============================================
echo ""
echo "==> Installing Go from official tarball..."

GO_VERSION="1.24.12"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://mirrors.aliyun.com/golang/${GO_TARBALL}"

GO_LOCAL_TARBALL=""
if [ -d "/share/golang" ]; then
    GO_LOCAL_TARBALL=$(ls -1 /share/golang/go*.linux-amd64.tar.gz 2>/dev/null | sort -V | tail -n1 || true)
fi

if [ -n "$GO_LOCAL_TARBALL" ]; then
    echo "==> Installing Go from local tarball: $GO_LOCAL_TARBALL"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$GO_LOCAL_TARBALL"
    sudo tee /etc/profile.d/go.sh > /dev/null <<'EOF'
export PATH="/usr/local/go/bin:${PATH}"
EOF
    export PATH="/usr/local/go/bin:${PATH}"
    go version
    echo "✓ Go installed from local tarball"
else
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
# 7. 安装并启用 qemu-guest-agent
# ============================================
echo ""
echo "==> Installing and enabling qemu-guest-agent..."

if ! dpkg -l | grep -q qemu-guest-agent; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent
fi

sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent

echo "✓ QEMU Guest Agent installed and enabled"

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
TimeoutStartSec=5s
EOF

echo "✓ Network wait timeout configured"

# ============================================
# 10. 预装 VS Code Server（避免首次连接下载）
# ============================================
echo ""
echo "==> Pre-installing VS Code Server..."

# 使用 dl-vscode-server 脚本安装 VS Code Server
# https://github.com/b01/dl-vscode-server
VSCODE_DIR="/etc/skel/.vscode-server"

# 创建目录并临时设置权限，允许脚本写入（脚本会在 HOME 目录创建符号链接）
sudo mkdir -p "$VSCODE_DIR"
sudo mkdir -p "/etc/skel/.vscode"
sudo chmod 777 /etc/skel
sudo chmod 777 "$VSCODE_DIR"
sudo chmod 777 "/etc/skel/.vscode"

# 使用本地 download-vs-code.sh 脚本（来自 b01/dl-vscode-server）
VSCODE_SCRIPT="/tmp/scripts/download-vs-code.sh"
chmod +x "$VSCODE_SCRIPT"

# 获取最新 stable commit ID
VSCODE_COMMIT=$(curl -fsSL "https://update.code.visualstudio.com/api/commits/stable/server-linux-x64" 2>/dev/null | sed 's/^\["\([^"]*\).*$/\1/')
echo "Latest VS Code stable commit: $VSCODE_COMMIT"

# 临时设置 HOME 为 /etc/skel，让脚本安装到骨架目录
export HOME="/etc/skel"

echo "Installing VS Code Server for Remote-SSH..."
"$VSCODE_SCRIPT" --use-commit "$VSCODE_COMMIT" linux x64

echo "Installing VS Code CLI..."
"$VSCODE_SCRIPT" --use-commit "$VSCODE_COMMIT" --cli linux x64

# 恢复正确的权限
sudo chmod 755 /etc/skel
sudo chmod -R 755 "$VSCODE_DIR"
sudo chmod -R 755 "/etc/skel/.vscode"

# 写入 commit ID 供 cloud-init 使用
echo "$VSCODE_COMMIT" | sudo tee "$VSCODE_DIR/.commit_id" > /dev/null
echo "✓ VS Code Server pre-installed (commit: $VSCODE_COMMIT)"

# 安装 VS Code Web（单独处理，dl-vscode-server 不支持）
echo "Installing VS Code Web..."
VSCODE_WEB_DIR="/opt/vscode-web"
sudo mkdir -p "$VSCODE_WEB_DIR"
if [ -n "$VSCODE_COMMIT" ]; then
    WEB_URL="https://update.code.visualstudio.com/commit:$VSCODE_COMMIT/server-linux-x64-web/stable"
    if curl -fsSL --retry 3 "$WEB_URL" -o "/tmp/vscode-web.tar.gz"; then
        sudo tar -xzf /tmp/vscode-web.tar.gz -C "$VSCODE_WEB_DIR" --strip-components=1
        sudo chmod +x "$VSCODE_WEB_DIR/bin/code-server" 2>/dev/null || true
        sudo chmod +x "$VSCODE_WEB_DIR/node" 2>/dev/null || true
        echo "$VSCODE_COMMIT" | sudo tee "$VSCODE_WEB_DIR/.commit_id" > /dev/null
        echo "✓ VS Code Web installed to $VSCODE_WEB_DIR"
        rm -f /tmp/vscode-web.tar.gz
    else
        echo "⚠️ VS Code Web download failed"
    fi
fi

# ============================================
# 11. 安装自定义脚本
# ============================================
echo ""
echo "==> Installing custom scripts..."

# 安装路由切换脚本
if [ -f "/tmp/scripts/route-switch.sh" ]; then
    sudo cp /tmp/scripts/route-switch.sh /usr/local/sbin/route-switch.sh
    sudo chmod +x /usr/local/sbin/route-switch.sh
    echo "✓ route-switch.sh installed"
else
    echo "⚠️ route-switch.sh not found in /tmp/scripts/"
fi

# 安装 NFS 挂载脚本
if [ -f "/tmp/scripts/mount-nfs-share.sh" ]; then
    sudo cp /tmp/scripts/mount-nfs-share.sh /usr/local/bin/mount-nfs-share.sh
    sudo chmod +x /usr/local/bin/mount-nfs-share.sh
    echo "✓ mount-nfs-share.sh installed"
else
    echo "⚠️ mount-nfs-share.sh not found in /tmp/scripts/"
fi

# ============================================
# 12. 写入模板构建时间
# ============================================
echo ""
echo "==> Writing template build metadata..."

BUILD_TIME_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
sudo tee /etc/template-build-info > /dev/null <<EOF
TEMPLATE_BUILD_TIME_UTC=${BUILD_TIME_UTC}
TEMPLATE_TYPE=cloud-image
EOF

echo "✓ Template build metadata written: ${BUILD_TIME_UTC}"

# ============================================
# 13. 切换回主路由
# ============================================
echo ""
echo "==> Switching back to main router..."

if [ -f "/usr/local/sbin/route-switch.sh" ]; then
    sudo /usr/local/sbin/route-switch.sh to-main || echo "⚠️ Route switch back failed"
else
    echo "⚠️ route-switch.sh not installed, skipping route switch"
fi

# ============================================
# 完成
# ============================================
echo ""
echo "============================================"
echo "System setup completed successfully!"
echo "============================================"
