set -euo pipefail

URL=https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/noble/current/noble-server-cloudimg-amd64.img
FILE=$(basename $URL)
CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="${CACHE_DIR}/${FILE}"

VMID=9001
NAME=ubuntu-2404-cloudimg-base
STORAGE=local-lvm
BRIDGE=vmbr0

mkdir -p "$CACHE_DIR"
if [[ -f "$CACHE_FILE" ]]; then
	echo "Cloudimg already exists: ${CACHE_FILE} (skip download)"
else
	echo "Downloading cloudimg to ${CACHE_FILE}..."
	curl -fsSL "$URL" -o "$CACHE_FILE"
fi

echo "Creating VM ${VMID} (${NAME})..."
if ! pvesm status --content images | awk 'NR>1{print $1}' | grep -qx "$STORAGE"; then
	echo "Storage not found: ${STORAGE}. Check STORAGE name (e.g. local-lvm)."
	exit 1
fi
qm create $VMID --name $NAME --memory 2048 --cores 2 --net0 virtio,bridge=$BRIDGE
echo "Importing disk to ${STORAGE}..."
qm importdisk $VMID "$CACHE_FILE" $STORAGE
qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VMID-disk-0
qm set $VMID --ide2 $STORAGE:cloudinit
qm set $VMID --boot c --bootdisk scsi0
qm set $VMID --serial0 socket --vga serial0

echo "Converting to template..."
qm template $VMID