#cloud-config
autoinstall:
  version: 1

  # ============================================
  # 区域设置
  # ============================================
  locale: en_US.UTF-8
  keyboard:
    layout: us

  # ============================================
  # 网络配置（使用 DHCP）
  # ============================================
  network:
    network:
      version: 2
      ethernets:
        ens18:
          dhcp4: true

  # ============================================
  # 存储配置（使用整个磁盘 + LVM）
  # ============================================
  storage:
    layout:
      name: lvm
      match:
        size: largest

  # ============================================
  # SSH 配置
  # ============================================
  ssh:
    install-server: true
    allow-pw: true

  # ============================================
  # 用户配置
  # ============================================
  # 创建 packer 用户（仅用于 SSH provisioning，后续会清理）
  identity:
    hostname: ubuntu-packer-template
    username: ${ssh_username}
    # 密码将在 late-commands 中设置
    password: "$6$rounds=4096$saltsalt$5wVcsOiB3CqLkZ7JnHQMhB8UH5VZdF1yLPzqIjZBqLKHLVLKHLVLKHLVLKH"

  # ============================================
  # 软件包配置
  # ============================================
  # 仅安装 cloud-init 必需的基础包
  packages:
    - qemu-guest-agent
    - cloud-init
    - cloud-initramfs-growroot

  # ============================================
  # 用户数据配置
  # ============================================
  user-data:
    disable_root: false
    package_update: false
    package_upgrade: false

  # ============================================
  # 安装后命令
  # ============================================
  late-commands:
    # 设置 packer 用户密码（使用 chpasswd）
    - "echo '${ssh_username}:${ssh_password}' | curtin in-target --target=/target -- chpasswd"

    # 配置 packer 用户的 sudo 权限
    - echo '${ssh_username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${ssh_username}
    - chmod 440 /target/etc/sudoers.d/${ssh_username}

    # 启用 qemu-guest-agent 和 SSH 服务
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent
    - curtin in-target --target=/target -- systemctl enable ssh
