output "vm_id" {
  description = "已创建虚拟机的 ID"
  value       = proxmox_virtual_environment_vm.ubuntu_vm.id
}

output "vm_name" {
  description = "已创建虚拟机的名称"
  value       = proxmox_virtual_environment_vm.ubuntu_vm.name
}

output "vm_node" {
  description = "虚拟机运行所在的 Proxmox 节点"
  value       = proxmox_virtual_environment_vm.ubuntu_vm.node_name
}

output "vm_ip_addresses" {
  description = "分配给虚拟机的 IP 地址"
  value       = proxmox_virtual_environment_vm.ubuntu_vm.ipv4_addresses
}

output "vm_mac_addresses" {
  description = "虚拟机网络接口的 MAC 地址"
  value       = proxmox_virtual_environment_vm.ubuntu_vm.mac_addresses
}

output "vm_status" {
  description = "虚拟机的当前状态"
  value       = proxmox_virtual_environment_vm.ubuntu_vm.started
}
