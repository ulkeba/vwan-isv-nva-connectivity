variable "name" {
  description = "Name of the Linux test VM and prefix for its dependent resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group in which to create the VM."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the VM."
  type        = string
}

variable "subnet_id" {
  description = "Resource ID of the subnet to which the VM is attached."
  type        = string
}

variable "network_security_group_id" {
  description = "Optional resource ID of the network security group applied to the VM NIC."
  type        = string
  default     = null
  nullable    = true
}

variable "private_ip_address" {
  description = "Optional static private IPv4 address. Azure assigns a dynamic address when null."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.private_ip_address == null || can(cidrnetmask("${var.private_ip_address}/32"))
    error_message = "private_ip_address must be null or a valid IPv4 address."
  }
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
}

variable "admin_username" {
  description = "Local administrator username."
  type        = string
}

variable "ssh_public_key" {
  description = "OpenSSH public key used for administrator access."
  type        = string
}

variable "zone" {
  description = "Optional availability zone for the VM."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || contains(["1", "2", "3"], var.zone)
    error_message = "zone must be null or one of \"1\", \"2\", or \"3\"."
  }
}

variable "custom_data" {
  description = "Optional unencoded cloud-init data."
  type        = string
  default     = null
}

variable "source_image_reference" {
  description = "Marketplace image used for the VM."
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
