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

variable "instance_count" {
  description = "Number of NVA instances to deploy."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 3 && floor(var.instance_count) == var.instance_count
    error_message = "instance_count must be an integer from 1 through 3."
  }
}

variable "zones" {
  description = "Optional distinct availability zone for each NVA VM; null deploys all instances non-zonally."
  type        = list(string)
  default     = ["1", "2"]
  nullable    = true

  validation {
    condition = var.zones == null || (
      length(var.zones) == var.instance_count &&
      length(distinct(var.zones)) == length(var.zones) &&
      alltrue([for zone in var.zones : contains(["1", "2", "3"], zone)])
    )
    error_message = "zones must be null or contain exactly instance_count distinct values chosen from \"1\", \"2\", and \"3\"."
  }
}

variable "vm_size" {
  description = "Azure VM size used by the NVA instances."
  type        = string
}

variable "admin_username" {
  description = "Local administrator username for the NVA instances."
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
  description = "ISV traffic IPv4 CIDR allowed through the NVA."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.isv_workload_address_prefix))
    error_message = "isv_workload_address_prefix must be a valid IPv4 CIDR."
  }
}

variable "source_image_reference" {
  description = "Marketplace image used for the NVA instances."
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
