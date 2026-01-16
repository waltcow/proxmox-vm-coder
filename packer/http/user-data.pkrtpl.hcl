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
        all:
          match:
            name: "en*"
          dhcp4: true
          dhcp6: false

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
    # 使用有效的密码哈希（MD5 crypt）
    password: "$1$8U.XHvTY$RkqySy4krtTiaSNpH8gR.."

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
    ssh_pwauth: true
    chpasswd:
      expire: false
      list: |
        ${ssh_username}:${ssh_password}

  # ============================================
  # 安装后命令
  # ============================================
  late-commands:
    # 标记 autoinstall 完成
    - curtin in-target --target=/target -- bash -c "echo 'autoinstall done' > /var/log/autoinstall.done"
    # 配置 packer 用户的 sudo 权限
    - echo '${ssh_username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${ssh_username}
    - chmod 440 /target/etc/sudoers.d/${ssh_username}

    # 启用 qemu-guest-agent 和 SSH 服务
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent
    - curtin in-target --target=/target -- systemctl enable ssh
