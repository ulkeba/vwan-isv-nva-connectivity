locals {
  ipv4_cidrs = {
    virtual_hub     = var.virtual_hub_address_prefix
    customer_vnet   = var.customer_virtual_network_address_space
    workload_subnet = var.customer_workload_subnet_prefix
    bastion_subnet  = var.customer_bastion_subnet_prefix
    isv_workload    = var.isv_workload_address_prefix
  }

  ipv4_ranges = {
    for name, cidr in local.ipv4_cidrs : name => try({
      first = sum([
        for index, octet in split(".", cidrhost(cidr, 0)) :
        parseint(octet, 10) * pow(256, 3 - index)
      ])
      last = sum([
        for index, octet in split(".", cidrhost(cidr, -1)) :
        parseint(octet, 10) * pow(256, 3 - index)
      ])
    }, null)
  }

  customer_workload_private_ip_integer = try(sum([
    for index, octet in split(".", var.customer_workload_private_ip_address) :
    parseint(octet, 10) * pow(256, 3 - index)
  ]), null)
}

resource "terraform_data" "input_validation" {
  lifecycle {
    precondition {
      condition     = !var.virtual_hub_route_private_traffic || var.virtual_hub_deploy_firewall
      error_message = "virtual_hub_route_private_traffic requires virtual_hub_deploy_firewall."
    }

    precondition {
      condition     = alltrue([for range in values(local.ipv4_ranges) : range != null])
      error_message = "All address plan inputs must be valid IPv4 CIDR prefixes."
    }

    precondition {
      condition = try(
        local.ipv4_ranges.customer_vnet.first <= local.ipv4_ranges.workload_subnet.first &&
        local.ipv4_ranges.customer_vnet.last >= local.ipv4_ranges.workload_subnet.last &&
        local.ipv4_ranges.customer_vnet.first <= local.ipv4_ranges.bastion_subnet.first &&
        local.ipv4_ranges.customer_vnet.last >= local.ipv4_ranges.bastion_subnet.last,
        false
      )
      error_message = "The workload and Bastion subnets must be fully contained in the customer VNet."
    }

    precondition {
      condition = try(
        local.ipv4_ranges.workload_subnet.last < local.ipv4_ranges.bastion_subnet.first ||
        local.ipv4_ranges.bastion_subnet.last < local.ipv4_ranges.workload_subnet.first,
        false
      )
      error_message = "The customer workload and Bastion subnets must not overlap."
    }

    precondition {
      condition = try(
        (
          local.ipv4_ranges.virtual_hub.last < local.ipv4_ranges.customer_vnet.first ||
          local.ipv4_ranges.customer_vnet.last < local.ipv4_ranges.virtual_hub.first
        ) &&
        (
          local.ipv4_ranges.isv_workload.last < local.ipv4_ranges.customer_vnet.first ||
          local.ipv4_ranges.customer_vnet.last < local.ipv4_ranges.isv_workload.first
        ),
        false
      )
      error_message = "The virtual hub, customer VNet, and ISV workload prefixes must not overlap."
    }

    precondition {
      condition     = try(tonumber(split("/", var.customer_bastion_subnet_prefix)[1]) <= 26, false)
      error_message = "AzureBastionSubnet must be /26 or larger."
    }

    precondition {
      condition = try(
        cidrhost("${var.customer_workload_private_ip_address}/32", 0) == var.customer_workload_private_ip_address &&
        local.customer_workload_private_ip_integer >= local.ipv4_ranges.workload_subnet.first &&
        local.customer_workload_private_ip_integer <= local.ipv4_ranges.workload_subnet.last,
        false
      )
      error_message = "The customer workload private IP must be a valid IPv4 address inside the workload subnet."
    }
  }
}
