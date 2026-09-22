variable "subscription_id" {
  description = "Customer Azure subscription ID."
  type        = string
}

variable "location" {
  description = "Azure region for all customer resources."
  type        = string
}

variable "customer_prefix" {
  description = "Prefix used to derive all customer resource names."
  type        = string
  default     = "fd-customer"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.customer_prefix))
    error_message = "customer_prefix must contain only lowercase letters, numbers, and internal hyphens."
  }
}

variable "virtual_hub_address_prefix" {
  description = "Address prefix assigned to the virtual hub."
  type        = string
}

variable "customer_virtual_network_address_space" {
  description = "Address space assigned to the customer virtual network."
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
