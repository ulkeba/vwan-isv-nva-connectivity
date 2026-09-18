variable "name_prefix" {
  description = "Prefix used to name the NVA VMs and load-balancer resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group in which to create the NVA cluster."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the NVA cluster."
  type        = string
}

variable "subnet_id" {
  description = "Resource ID of the NVA subnet."
  type        = string
}

variable "network_security_group_id" {
  description = "Resource ID of the network security group applied to each NVA NIC."
  type        = string
  default     = null
  nullable    = true
}

variable "frontend_private_ip_address" {
  description = "Static private IPv4 address of the load-balancer frontend."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.frontend_private_ip_address}/32"))
    error_message = "frontend_private_ip_address must be a valid IPv4 address."
  }
}

variable "health_probe_port" {
  description = "TCP port used by the Azure Load Balancer health probe."
  type        = number

  validation {
    condition     = var.health_probe_port >= 1 && var.health_probe_port <= 65535
    error_message = "health_probe_port must be between 1 and 65535."
  }
}

variable "zones" {
  description = "Two distinct availability zones for the NVA VMs."
  type        = list(string)

  validation {
    condition     = length(var.zones) == 2 && length(distinct(var.zones)) == 2
    error_message = "zones must contain exactly two distinct availability zones."
  }

  validation {
    condition     = alltrue([for zone in var.zones : contains(["1", "2", "3"], zone)])
    error_message = "Each NVA zone must be one of \"1\", \"2\", or \"3\"."
  }
}

variable "vm_size" {
  description = "Azure VM size used by both NVA instances."
  type        = string
}

variable "admin_username" {
  description = "Local administrator username for both NVA instances."
  type        = string
}

variable "ssh_public_key" {
  description = "OpenSSH public key used for NVA administrator access."
  type        = string
}

variable "customer_address_prefix" {
  description = "Customer workload IPv4 CIDR allowed through the NVA."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.customer_address_prefix))
    error_message = "customer_address_prefix must be a valid IPv4 CIDR."
  }
}

variable "isv_workload_address_prefix" {
  description = "ISV workload IPv4 CIDR allowed through the NVA."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.isv_workload_address_prefix))
    error_message = "isv_workload_address_prefix must be a valid IPv4 CIDR."
  }
}

variable "source_image_reference" {
  description = "Marketplace image used for both NVA instances."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
