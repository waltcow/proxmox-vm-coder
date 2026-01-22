#!/bin/bash

echo "Waiting for network to be ready..."
# 等待网络就绪：检查能否 ping 通 NFS 服务器
for i in {1..3}; do
  if ping -c 1 -W 2 192.168.50.60 >/dev/null 2>&1; then
    echo "✓ Network is ready (attempt $i)"
    break
  fi
  echo "Waiting for network... (attempt $i/3)"
  sleep 2
done

mkdir -p "/share"

# 重试逻辑：尝试最多3次
for i in {1..3}; do
  if mount -t nfs -o soft,timeo=10,retrans=2 "192.168.50.60:/share" "/share"; then
    echo "✓ NFS share mounted on attempt $i"
    break
  else
    echo "NFS mount failed (attempt $i/3), retrying in 2 seconds..."
    sleep 2
    if [ $i -eq 3 ]; then
      echo "ERROR: Failed to mount NFS share after 3 attempts"
      exit 1
    fi
  fi
done

# 添加到 fstab（如果还没有）
if ! grep -q "192.168.50.60:/share" /etc/fstab; then
  printf '%s\n' "192.168.50.60:/share /share nfs defaults,_netdev,soft,timeo=10 0 0" >> "/etc/fstab"
  echo "✓ Added NFS share to fstab"
fi

systemctl daemon-reload
echo "✓ NFS share setup complete"
