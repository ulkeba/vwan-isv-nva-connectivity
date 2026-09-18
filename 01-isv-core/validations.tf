locals {
  ipv4_cidrs = {
    virtual_network = var.virtual_network_address_space
    nva             = var.nva_subnet_address_prefix
    workload        = var.workload_subnet_address_prefix
    bastion         = var.bastion_subnet_address_prefix
    customer        = var.customer_address_prefix
  }

  ipv4_cidr_parts = {
    for name, cidr in local.ipv4_cidrs : name => {
      address = try(sum([
        for index, octet in split(".", split("/", cidr)[0]) :
        tonumber(octet) * pow(256, 3 - index)
      ]), -1)
      prefix_length = try(tonumber(split("/", cidr)[1]), -1)
    }
  }

  ipv4_cidr_ranges = {
    for name, parts in local.ipv4_cidr_parts : name => {
      first = try(floor(parts.address / pow(2, 32 - parts.prefix_length)) * pow(2, 32 - parts.prefix_length), -1)
      last  = try(floor(parts.address / pow(2, 32 - parts.prefix_length)) * pow(2, 32 - parts.prefix_length) + pow(2, 32 - parts.prefix_length) - 1, -1)
    }
  }

  nva_frontend_ip_number = try(sum([
    for index, octet in split(".", var.nva_frontend_private_ip_address) :
    tonumber(octet) * pow(256, 3 - index)
  ]), -1)

  workload_vm_ip_number = try(sum([
    for index, octet in split(".", var.workload_vm_private_ip_address) :
    tonumber(octet) * pow(256, 3 - index)
  ]), -1)
}

variable "subscription_id" {
  description = "Azure subscription ID in which the ISV core is deployed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "virtual_network_address_space" {
  description = "IPv4 CIDR for the ISV virtual network."
  type        = string

  validation {
    condition     = can(cidrhost(var.virtual_network_address_space, 0)) && !strcontains(var.virtual_network_address_space, ":")
    error_message = "virtual_network_address_space must be a valid IPv4 CIDR."
  }

}

variable "nva_subnet_address_prefix" {
  description = "IPv4 CIDR for the NVA subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.nva_subnet_address_prefix, 0)) && !strcontains(var.nva_subnet_address_prefix, ":")
    error_message = "nva_subnet_address_prefix must be a valid IPv4 CIDR."
  }

}

variable "workload_subnet_address_prefix" {
  description = "IPv4 CIDR for the ISV workload subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.workload_subnet_address_prefix, 0)) && !strcontains(var.workload_subnet_address_prefix, ":")
    error_message = "workload_subnet_address_prefix must be a valid IPv4 CIDR."
  }
}

variable "bastion_subnet_address_prefix" {
  description = "IPv4 CIDR for AzureBastionSubnet."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.bastion_subnet_address_prefix, 0)) &&
      !strcontains(var.bastion_subnet_address_prefix, ":") &&
      try(tonumber(split("/", var.bastion_subnet_address_prefix)[1]) <= 26, false)
    )
    error_message = "bastion_subnet_address_prefix must be a valid IPv4 /26 or larger."
  }
}

variable "customer_address_prefix" {
  description = "IPv4 CIDR of the customer network that the NVAs forward."
  type        = string

  validation {
    condition     = can(cidrhost(var.customer_address_prefix, 0)) && !strcontains(var.customer_address_prefix, ":")
    error_message = "customer_address_prefix must be a valid IPv4 CIDR."
  }
}

variable "nva_frontend_private_ip_address" {
  description = "Static private address of the NVA internal load balancer."
  type        = string

  validation {
    condition     = can(cidrhost("${var.nva_frontend_private_ip_address}/32", 0)) && !strcontains(var.nva_frontend_private_ip_address, ":")
    error_message = "nva_frontend_private_ip_address must be a valid IPv4 address."
  }
}

variable "workload_vm_private_ip_address" {
  description = "Static private IPv4 address for the workload VM."
  type        = string

  validation {
    condition     = can(cidrhost("${var.workload_vm_private_ip_address}/32", 0)) && !strcontains(var.workload_vm_private_ip_address, ":")
    error_message = "workload_vm_private_ip_address must be a valid IPv4 address."
  }
}

variable "nva_zones" {
  description = "Two distinct availability zones for the NVA pair."
  type        = list(string)

  validation {
    condition     = length(var.nva_zones) == 2 && length(distinct(var.nva_zones)) == 2 && alltrue([for zone in var.nva_zones : contains(["1", "2", "3"], zone)])
    error_message = "nva_zones must contain exactly two distinct Azure availability zones (1, 2, or 3)."
  }
}

variable "health_probe_port" {
  description = "TCP port used by the load balancer health probe."
  type        = number

  validation {
    condition     = var.health_probe_port >= 1 && var.health_probe_port <= 65535
    error_message = "health_probe_port must be between 1 and 65535."
  }
}

variable "workload_vm_zone" {
  description = "Availability zone for the workload test VM."
  type        = string

  validation {
    condition     = contains(["1", "2", "3"], var.workload_vm_zone)
    error_message = "workload_vm_zone must be 1, 2, or 3."
  }
}

variable "admin_username" {
  description = "Administrator username for all Linux VMs."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.admin_username))
    error_message = "admin_username must be a valid Linux username of at most 32 characters."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the local OpenSSH public key file."
  type        = string

  validation {
    condition     = fileexists(pathexpand(var.ssh_public_key_path))
    error_message = "ssh_public_key_path must identify an existing local public key file."
  }
}

resource "terraform_data" "input_validation" {
  lifecycle {
    precondition {
      condition = alltrue([
        for subnet in ["nva", "workload", "bastion"] :
        local.ipv4_cidr_ranges[subnet].first >= local.ipv4_cidr_ranges.virtual_network.first &&
        local.ipv4_cidr_ranges[subnet].last <= local.ipv4_cidr_ranges.virtual_network.last
      ])
      error_message = "Every ISV subnet must be fully contained in the ISV virtual network."
    }

    precondition {
      condition = (
        local.ipv4_cidr_ranges.virtual_network.last < local.ipv4_cidr_ranges.customer.first ||
        local.ipv4_cidr_ranges.customer.last < local.ipv4_cidr_ranges.virtual_network.first
      )
      error_message = "The customer and ISV virtual network prefixes must not overlap."
    }

    precondition {
      condition = (
        (
          local.ipv4_cidr_ranges.nva.last < local.ipv4_cidr_ranges.workload.first ||
          local.ipv4_cidr_ranges.workload.last < local.ipv4_cidr_ranges.nva.first
        ) &&
        (
          local.ipv4_cidr_ranges.nva.last < local.ipv4_cidr_ranges.bastion.first ||
          local.ipv4_cidr_ranges.bastion.last < local.ipv4_cidr_ranges.nva.first
        ) &&
        (
          local.ipv4_cidr_ranges.workload.last < local.ipv4_cidr_ranges.bastion.first ||
          local.ipv4_cidr_ranges.bastion.last < local.ipv4_cidr_ranges.workload.first
        )
      )
      error_message = "The NVA, workload, and Bastion subnet prefixes must not overlap."
    }

    precondition {
      condition = (
        local.nva_frontend_ip_number >= local.ipv4_cidr_ranges.nva.first + 4 &&
        local.nva_frontend_ip_number < local.ipv4_cidr_ranges.nva.last
      )
      error_message = "nva_frontend_private_ip_address must be an assignable address inside the NVA subnet."
    }

    precondition {
      condition = (
        local.workload_vm_ip_number >= local.ipv4_cidr_ranges.workload.first &&
        local.workload_vm_ip_number <= local.ipv4_cidr_ranges.workload.last
      )
      error_message = "workload_vm_private_ip_address must be inside the workload subnet."
    }
  }
}
