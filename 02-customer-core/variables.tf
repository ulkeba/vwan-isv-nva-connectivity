variable "subscription_id" {
  description = "Customer Azure subscription ID."
  type        = string
}

variable "location" {
  description = "Azure region for all customer resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the customer resource group."
  type        = string
}

variable "virtual_wan_name" {
  description = "Name of the Standard Virtual WAN."
  type        = string
}

variable "virtual_hub_name" {
  description = "Name of the Virtual WAN hub."
  type        = string
}

variable "virtual_hub_address_prefix" {
  description = "Address prefix assigned to the virtual hub."
  type        = string
}

variable "customer_virtual_network_name" {
  description = "Name of the customer virtual network."
  type        = string
}

variable "customer_virtual_network_address_space" {
  description = "Address space assigned to the customer virtual network."
  type        = string
}

variable "customer_workload_subnet_name" {
  description = "Name of the customer workload subnet."
  type        = string
}

variable "customer_workload_subnet_prefix" {
  description = "Address prefix assigned to the customer workload subnet."
  type        = string
}

variable "customer_bastion_subnet_prefix" {
  description = "Address prefix assigned to AzureBastionSubnet."
  type        = string
}

variable "isv_workload_address_prefix" {
  description = "ISV workload prefix permitted by the customer workload NSG."
  type        = string
}

variable "customer_workload_network_security_group_name" {
  description = "Name of the customer workload network security group."
  type        = string
}

variable "customer_workload_vm_name" {
  description = "Name of the customer workload virtual machine."
  type        = string
}

variable "customer_workload_private_ip_address" {
  description = "Static private IP address assigned to the customer workload VM."
  type        = string
}

variable "customer_workload_vm_size" {
  description = "Azure VM size for the customer workload VM."
  type        = string
}

variable "customer_workload_admin_username" {
  description = "Administrator username for the customer workload VM."
  type        = string
}

variable "customer_workload_ssh_public_key_path" {
  description = "Path to the SSH public key for the customer workload VM."
  type        = string
}

variable "customer_workload_zone" {
  description = "Availability zone for the customer workload VM."
  type        = string
}

variable "customer_bastion_public_ip_name" {
  description = "Name of the customer Bastion public IP."
  type        = string
}

variable "customer_bastion_name" {
  description = "Name of the customer Bastion host."
  type        = string
}

variable "customer_workload_connection_name" {
  description = "Name of the customer workload VNet-to-hub connection."
  type        = string
}
