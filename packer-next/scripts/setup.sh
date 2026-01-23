#!/bin/bash
# Packer System Setup Script
# Configures Ubuntu 24.04: mirrors, packages, runtimes (Node.js/Go), and VS Code.

set -euo pipefail

# ============================================
# Configuration
# ============================================
GO_VERSION="1.24.0"
NODE_VERSION="24.x"
PNPM_VERSION="latest-10"

# Paths
NFS_SHARE_DIR="/share"
VSCODE_SERVER_DIR="/etc/skel/.vscode-server"
VSCODE_WEB_DIR="/opt/vscode-web"
TMP_SCRIPTS_DIR="/tmp/scripts"

# URLs
TSINGHUA_UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
NPM_REGISTRY="https://registry.npmmirror.com"

# Logging Helpers
log() { echo -e "\n\033[1;32m==> $1\033[0m"; }
warn() { echo -e "\033[1;33m⚠️  $1\033[0m"; }
error() { echo -e "\033[1;31m❌ $1\033[0m"; exit 1; }

# ============================================
# 0. Fix script permissions (Packer file provisioner doesn't preserve +x)
# ============================================
if [ -d "${TMP_SCRIPTS_DIR}" ]; then
    chmod +x "${TMP_SCRIPTS_DIR}"/*.sh 2>/dev/null || true
fi

# ============================================
# 0.1 Network & Routing
# ============================================
log "Switching to bypass router for external network access..."
if [ -x "${TMP_SCRIPTS_DIR}/route-switch.sh" ]; then
    sudo "${TMP_SCRIPTS_DIR}/route-switch.sh" to-bypass || warn "Route switch failed, continuing..."
else
    warn "route-switch.sh not found."
fi

# ============================================
# 1. Configure Mirrors
# ============================================
log "Configuring Tsinghua University Ubuntu mirrors..."
if [ -f "/etc/apt/sources.list.d/ubuntu.sources" ]; then
    sudo mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.disabled
fi

cat <<EOF | sudo tee /etc/apt/sources.list > /dev/null
deb ${TSINGHUA_UBUNTU_MIRROR} noble main restricted universe multiverse
deb ${TSINGHUA_UBUNTU_MIRROR} noble-updates main restricted universe multiverse
deb ${TSINGHUA_UBUNTU_MIRROR} noble-backports main restricted universe multiverse
deb ${TSINGHUA_UBUNTU_MIRROR} noble-security main restricted universe multiverse
EOF

# ============================================
# 2. Update & Install Packages
# ============================================
log "Updating package index and installing base packages..."
sudo apt-get update

DEBIAN_FRONTEND=noninteractive sudo apt-get install -y \
    curl ca-certificates git net-tools jq wget \
    apt-transport-https gnupg software-properties-common nfs-common

# ============================================
# 3. Mount NFS (Optional)
# ============================================
log "Attempting to mount NFS share..."
if [ -x "${TMP_SCRIPTS_DIR}/mount-nfs-share.sh" ]; then
    if sudo "${TMP_SCRIPTS_DIR}/mount-nfs-share.sh"; then
        log "NFS share mounted."
    else
        warn "NFS mount failed, falling back to remote downloads."
    fi
else
    warn "mount-nfs-share.sh not found."
fi

# ============================================
# 4. Install Node.js
# ============================================
log "Installing Node.js..."

install_node_local() {
    local tarball="$1"
    log "Installing Node.js from local tarball: $tarball"
    sudo rm -rf /usr/local/node
    sudo mkdir -p /usr/local/node
    sudo tar -xJf "$tarball" -C /usr/local/node --strip-components=1
    
    # Profile setup
    echo 'export PATH="/usr/local/node/bin:${PATH}"' | sudo tee /etc/profile.d/node.sh > /dev/null
    
    # Symlinks
    for bin in node npm npx; do
        sudo ln -sf "/usr/local/node/bin/$bin" "/usr/local/bin/$bin"
    done
}

install_node_remote() {
    log "Installing Node.js via NodeSource..."
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
    sudo apt-get update
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y nodejs
}

NODE_TARBALL=$(find "${NFS_SHARE_DIR}/nodejs" -name "node-v*-linux-x64.tar.xz" 2>/dev/null | sort -V | tail -n1 || true)
if [ -n "$NODE_TARBALL" ]; then
    install_node_local "$NODE_TARBALL"
else
    install_node_remote
fi

# Verification
export PATH="/usr/local/node/bin:${PATH}"
node -v && npm -v

log "Installing pnpm..."
sudo npm install -g "pnpm@${PNPM_VERSION}" --registry="${NPM_REGISTRY}"
pnpm -v

log "Configuring npm registry..."
sudo npm config set registry "${NPM_REGISTRY}" -g
npm config set registry "${NPM_REGISTRY}"

# Set registry for future users
echo "registry=${NPM_REGISTRY}" | sudo tee /etc/skel/.npmrc > /dev/null

log "Installing global npm packages..."

echo "Installing Claude Code CLI..."
sudo npm install -g @anthropic-ai/claude-code --registry="${NPM_REGISTRY}"
echo "Installing Gemini CLI..."
sudo npm install -g @google/gemini-cli --registry="${NPM_REGISTRY}"

echo "Installing OpenAI CLI..."
sudo npm install -g @openai/codex --registry="${NPM_REGISTRY}"

log "Installing Go..."

install_go_local() {
    local tarball="$1"
    log "Installing Go from local tarball: $tarball"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$tarball"
}

install_go_remote() {
    local version="$1"
    local tarball="go${version}.linux-amd64.tar.gz"
    local url="https://mirrors.aliyun.com/golang/${tarball}"
    log "Downloading Go ${version} from ${url}..."
    
    curl -fsSL "${url}" -o "/tmp/${tarball}"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${tarball}"
    rm -f "/tmp/${tarball}"
}

GO_LOCAL_TARBALL=$(find "${NFS_SHARE_DIR}/golang" -name "go*.linux-amd64.tar.gz" 2>/dev/null | sort -V | tail -n1 || true)

if [ -n "$GO_LOCAL_TARBALL" ]; then
    install_go_local "$GO_LOCAL_TARBALL"
else
    install_go_remote "$GO_VERSION"
fi

# Setup Go environment
echo 'export PATH="/usr/local/go/bin:${PATH}"' | sudo tee /etc/profile.d/go.sh > /dev/null
export PATH="/usr/local/go/bin:${PATH}"
go version

# ============================================
# 5. System Configuration
# ============================================
log "Disabling automatic updates..."
sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer || true
sudo systemctl mask apt-daily.service apt-daily-upgrade.service || true

log "Configuring qemu-guest-agent..."
if ! dpkg -l | grep -q qemu-guest-agent; then
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y qemu-guest-agent
fi
sudo systemctl enable --now qemu-guest-agent

log "Configuring cloud-init..."
echo "datasource_list: [ ConfigDrive, NoCloud, None ]" | sudo tee /etc/cloud/cloud.cfg.d/90_dpkg.cfg > /dev/null

log "Reducing systemd-networkd wait timeout..."
sudo mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
echo -e "[Service]\nTimeoutStartSec=5s" | sudo tee /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf > /dev/null

# ============================================
# 6. VS Code (Pre-install)
# ============================================
log "Pre-installing VS Code..."

# Check for local VS Code Web tarball
VSCODE_WEB_TARBALL=$(find "${NFS_SHARE_DIR}/vscode" -name "vscode-server-linux-x64-web*.tar.gz" 2>/dev/null | sort -V | tail -n1 || true)

# Extract commit from local tarball or fetch from remote
if [ -n "$VSCODE_WEB_TARBALL" ]; then
    VSCODE_COMMIT=$(basename "$VSCODE_WEB_TARBALL" | sed -n 's/.*-web-\([a-f0-9]*\)\.tar\.gz/\1/p')
    log "Using local VS Code commit: ${VSCODE_COMMIT}"
else
    VSCODE_COMMIT=$(curl -fsSL "https://update.code.visualstudio.com/api/commits/stable/server-linux-x64" | sed 's/^\["\([^"]*\).*$/\1/')
    log "Latest VS Code stable commit: ${VSCODE_COMMIT}"
fi

# Use a temporary home for installation
TMP_HOME=$(mktemp -d)
cp "${TMP_SCRIPTS_DIR}/download-vs-code.sh" "${TMP_HOME}/"
chmod +x "${TMP_HOME}/download-vs-code.sh"
export HOME="${TMP_HOME}"

# Install VS Code Server (for Remote SSH)
log "Installing VS Code Server..."
VSCODE_SERVER_TARBALL=$(find "${NFS_SHARE_DIR}/vscode" -name "vscode-server-linux-x64-${VSCODE_COMMIT}.tar.gz" 2>/dev/null | head -n1 || true)
if [ -n "$VSCODE_SERVER_TARBALL" ]; then
    log "Installing VS Code Server from local tarball"
    sudo mkdir -p "${VSCODE_SERVER_DIR}/bin/${VSCODE_COMMIT}"
    sudo mkdir -p "${VSCODE_SERVER_DIR}/extensions"
    sudo mkdir -p "${VSCODE_SERVER_DIR}/extensionsCache"
    sudo mkdir -p "${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}"
    sudo mkdir -p "/etc/skel/.vscode/cli/servers/Stable-${VSCODE_COMMIT}"
    sudo tar -xzf "$VSCODE_SERVER_TARBALL" -C "${VSCODE_SERVER_DIR}/bin/${VSCODE_COMMIT}" --strip-components=1
    # Create symlinks for CLI server discovery
    sudo ln -sf "${VSCODE_SERVER_DIR}/bin/${VSCODE_COMMIT}" "${VSCODE_SERVER_DIR}/bin/default_version"
    sudo ln -sf "${VSCODE_SERVER_DIR}/bin/${VSCODE_COMMIT}" "${VSCODE_SERVER_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server"
    sudo ln -sf "${VSCODE_SERVER_DIR}/bin/${VSCODE_COMMIT}" "/etc/skel/.vscode/cli/servers/Stable-${VSCODE_COMMIT}/server"
else
    "${TMP_HOME}/download-vs-code.sh" --use-commit "${VSCODE_COMMIT}" linux x64
fi

# Install VS Code CLI
log "Installing VS Code CLI..."
VSCODE_CLI_TARBALL=$(find "${NFS_SHARE_DIR}/vscode" -name "vscode-cli-linux-x64-${VSCODE_COMMIT}.tar.gz" 2>/dev/null | head -n1 || true)
if [ -n "$VSCODE_CLI_TARBALL" ]; then
    log "Installing VS Code CLI from local tarball"
    sudo tar -xzf "$VSCODE_CLI_TARBALL" -C "${VSCODE_SERVER_DIR}" --no-same-owner
    sudo ln -sf "${VSCODE_SERVER_DIR}/code" "${VSCODE_SERVER_DIR}/code-${VSCODE_COMMIT}"
else
    "${TMP_HOME}/download-vs-code.sh" --use-commit "${VSCODE_COMMIT}" --cli linux x64
fi

# Install VS Code Web
log "Installing VS Code Web..."
if [ -n "$VSCODE_WEB_TARBALL" ]; then
    log "Installing VS Code Web from local tarball"
    sudo mkdir -p "${VSCODE_WEB_DIR}"
    sudo tar -xzf "$VSCODE_WEB_TARBALL" -C "${VSCODE_WEB_DIR}" --strip-components=1
    sudo chmod +x "${VSCODE_WEB_DIR}/bin/code-server" "${VSCODE_WEB_DIR}/node"
else
    "${TMP_HOME}/download-vs-code.sh" --use-commit "${VSCODE_COMMIT}" --web linux x64
    if [ -d "${TMP_HOME}/.vscode-web" ]; then
        sudo mkdir -p "${VSCODE_WEB_DIR}"
        sudo cp -r "${TMP_HOME}/.vscode-web"/* "${VSCODE_WEB_DIR}/"
    fi
fi

# Copy Server/CLI artifacts to /etc/skel
if [ -d "${TMP_HOME}/.vscode-server" ]; then
    sudo mkdir -p "${VSCODE_SERVER_DIR}"
    sudo cp -r "${TMP_HOME}/.vscode-server"/* "${VSCODE_SERVER_DIR}/"
fi
if [ -d "${TMP_HOME}/.vscode" ]; then
    sudo mkdir -p "/etc/skel/.vscode"
    sudo cp -r "${TMP_HOME}/.vscode"/* "/etc/skel/.vscode/"
fi

# Write commit IDs
echo "${VSCODE_COMMIT}" | sudo tee "${VSCODE_SERVER_DIR}/.commit_id" > /dev/null
echo "${VSCODE_COMMIT}" | sudo tee "${VSCODE_WEB_DIR}/.commit_id" > /dev/null

# Set permissions
sudo chmod -R 755 "${VSCODE_SERVER_DIR}" "${VSCODE_WEB_DIR}"
[ -d "/etc/skel/.vscode" ] && sudo chmod -R 755 "/etc/skel/.vscode"

# Clean up
rm -rf "${TMP_HOME}"
log "VS Code installation completed."

# ============================================
# 7. Install Custom Scripts
# ============================================
log "Installing custom scripts..."

install_script() {
    local src="$1"
    local dest="$2"
    if [ -f "$src" ]; then
        sudo cp "$src" "$dest"
        sudo chmod +x "$dest"
        echo "✓ Installed $(basename "$dest")"
    else
        warn "$(basename "$dest") not found."
    fi
}

install_script "${TMP_SCRIPTS_DIR}/route-switch.sh" "/usr/local/sbin/route-switch.sh"
install_script "${TMP_SCRIPTS_DIR}/mount-nfs-share.sh" "/usr/local/bin/mount-nfs-share.sh"

# ============================================
# 8. Finalize
# ============================================
log "Writing template metadata..."
cat <<EOF | sudo tee /etc/template-build-info > /dev/null
TEMPLATE_BUILD_TIME_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TEMPLATE_TYPE=cloud-image
GO_VERSION=${GO_VERSION}
NODE_VERSION=$(node -v || echo "not installed")
PNPM_VERSION=$(pnpm -v || echo "not installed")
VSCODE_COMMIT=${VSCODE_COMMIT}
VSCODE_SERVER_DIR=${VSCODE_SERVER_DIR}
VSCODE_WEB_DIR=${VSCODE_WEB_DIR}
EOF

log "Switching back to main router..."
if [ -x "/usr/local/sbin/route-switch.sh" ]; then
    sudo "/usr/local/sbin/route-switch.sh" to-main || warn "Route switch back failed."
fi

log "System setup completed successfully!"
