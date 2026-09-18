variable "subscription_id" {
  description = "Azure subscription ID containing the ISV workload subnet."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "customer_address_prefix" {
  description = "IPv4 CIDR of the customer virtual network."
  type        = string

  validation {
    condition     = can(cidrhost(var.customer_address_prefix, 0)) && !strcontains(var.customer_address_prefix, ":")
    error_message = "customer_address_prefix must be a valid IPv4 CIDR."
  }
}

variable "nva_frontend_private_ip_address" {
  description = "Private IPv4 address of the NVA load balancer frontend."
  type        = string

  validation {
    condition     = can(cidrhost("${var.nva_frontend_private_ip_address}/32", 0)) && !strcontains(var.nva_frontend_private_ip_address, ":")
    error_message = "nva_frontend_private_ip_address must be a valid IPv4 address."
  }

  validation {
    condition = try(
      !(
        sum([
          for index, octet in split(".", var.nva_frontend_private_ip_address) :
          tonumber(octet) * pow(256, 3 - index)
          ]) >= floor(
          sum([
            for index, octet in split(".", split("/", var.customer_address_prefix)[0]) :
            tonumber(octet) * pow(256, 3 - index)
          ]) / pow(2, 32 - tonumber(split("/", var.customer_address_prefix)[1]))
        ) * pow(2, 32 - tonumber(split("/", var.customer_address_prefix)[1])) &&
        sum([
          for index, octet in split(".", var.nva_frontend_private_ip_address) :
          tonumber(octet) * pow(256, 3 - index)
          ]) <= floor(
          sum([
            for index, octet in split(".", split("/", var.customer_address_prefix)[0]) :
            tonumber(octet) * pow(256, 3 - index)
          ]) / pow(2, 32 - tonumber(split("/", var.customer_address_prefix)[1]))
        ) * pow(2, 32 - tonumber(split("/", var.customer_address_prefix)[1])) +
        pow(2, 32 - tonumber(split("/", var.customer_address_prefix)[1])) - 1
      ),
      true
    )
    error_message = "The NVA next-hop address must not be inside the customer destination prefix."
  }
}

variable "isv_workload_subnet_id" {
  description = "Resource ID of the ISV workload subnet."
  type        = string

  validation {
    condition = can(regex(
      "(?i)^/subscriptions/${var.subscription_id}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$",
      var.isv_workload_subnet_id
    ))
    error_message = "isv_workload_subnet_id must be a subnet resource ID in subscription_id."
  }
}
