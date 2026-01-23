#!/bin/bash
# Packer Cleanup Script
# Prepares the system for cloning by cleaning up logs, cache, keys, and identifiers.

set -euo pipefail

# ============================================
# Helpers
# ============================================
log() { echo -e "\n\033[1;32m==> $1\033[0m"; }

# ============================================
# 1. Stop Services
# ============================================
log "Stopping services..."
sudo systemctl stop qemu-guest-agent || true

# ============================================
# 2. Cleanup APT
# ============================================
log "Cleaning APT cache..."
sudo apt-get autoremove -y
sudo apt-get autoclean -y
sudo apt-get clean -y
sudo rm -rf /var/lib/apt/lists/*

# ============================================
# 3. Cleanup Logs
# ============================================
log "Cleaning logs..."
# Truncate all logs to 0 size
sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
# Remove archived logs
sudo find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete
sudo journalctl --vacuum-time=1s

# ============================================
# 4. Cleanup Temp Files
# ============================================
log "Cleaning temporary files..."
sudo rm -rf /tmp/* /var/tmp/*

# ============================================
# 5. Reset Machine Identity
# ============================================
log "Removing SSH host keys and machine-id..."
sudo rm -f /etc/ssh/ssh_host_*

# Reset machine-id (maintain the file but empty, and ensure dbus symlink)
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

# ============================================
# 6. Cleanup Cloud-Init
# ============================================
log "Cleaning cloud-init state and configurations..."

CLOUD_CONFIG_FILES=(
    "/etc/cloud/cloud.cfg.d/50-curtin-networking.cfg"
    "/etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg"
    "/etc/cloud/cloud.cfg.d/90-installer-network.cfg"
    "/etc/cloud/cloud.cfg.d/99-installer.cfg"
    "/etc/cloud/cloud-init.disabled"
    "/etc/netplan/50-cloud-init.yaml"
    "/etc/netplan/00-installer-config.yaml"
)

sudo rm -f "${CLOUD_CONFIG_FILES[@]}"
sudo cloud-init clean --logs --seed

# ============================================
# 7. Cleanup User Data
# ============================================
log "Cleaning user cache and history..."
sudo rm -rf ~/.cache/* ~/.config/*

# Clear history for current user and root
history -c
cat /dev/null > ~/.bash_history
sudo sh -c ': > /root/.bash_history' 2>/dev/null || true

# ============================================
# 8. Finalize
# ============================================
log "Syncing filesystem..."
sync

log "Cleanup completed successfully!"
echo "System is ready to be converted to template."
