variable "location" {
  description = "Azure region for all ISV core resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the ISV resource group."
  type        = string
}

variable "virtual_network_name" {
  description = "Name of the ISV virtual network."
  type        = string
}

variable "nva_subnet_name" {
  description = "Name of the NVA subnet."
  type        = string
}

variable "workload_subnet_name" {
  description = "Name of the ISV workload subnet."
  type        = string
}

variable "nva_name_prefix" {
  description = "Name prefix for NVA cluster resources."
  type        = string
}

variable "nva_network_security_group_name" {
  description = "Name of the NVA network security group."
  type        = string
}

variable "nva_vm_size" {
  description = "Azure VM size for each NVA."
  type        = string
}

variable "workload_vm_name" {
  description = "Name of the ISV workload test VM."
  type        = string
}

variable "workload_network_security_group_name" {
  description = "Name of the workload VM network security group."
  type        = string
}

variable "workload_vm_size" {
  description = "Azure VM size for the workload test VM."
  type        = string
}

variable "bastion_name" {
  description = "Name of the Azure Bastion host."
  type        = string
}

variable "bastion_public_ip_name" {
  description = "Name of the public IP used only by Azure Bastion."
  type        = string
}
