resource "terraform_data" "input_validation" {
  lifecycle {
    precondition {
      condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
      error_message = "subscription_id must be a valid UUID."
    }

    precondition {
      condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualHubs/[^/]+$", var.virtual_hub_id))
      error_message = "virtual_hub_id must be a complete Azure Virtual Hub resource ID."
    }

    precondition {
      condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.isv_virtual_network_id))
      error_message = "isv_virtual_network_id must be a complete Azure Virtual Network resource ID."
    }

    precondition {
      condition     = can(cidrhost(var.isv_workload_address_prefix, 0)) && !strcontains(var.isv_workload_address_prefix, ":")
      error_message = "isv_workload_address_prefix must be a valid IPv4 CIDR prefix."
    }

    precondition {
      condition     = can(cidrhost("${var.nva_load_balancer_frontend_ip_address}/32", 0)) && !strcontains(var.nva_load_balancer_frontend_ip_address, ":")
      error_message = "nva_load_balancer_frontend_ip_address must be a valid IPv4 address."
    }

    precondition {
      condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualHubs/[^/]+/hubRouteTables/[^/]+$", var.associated_route_table_id))
      error_message = "associated_route_table_id must be a complete Virtual Hub Route Table resource ID."
    }

    precondition {
      condition     = startswith(lower(var.associated_route_table_id), "${lower(var.virtual_hub_id)}/hubroutetables/")
      error_message = "associated_route_table_id must belong to virtual_hub_id."
    }

    precondition {
      condition     = startswith(lower(var.virtual_hub_id), "/subscriptions/${lower(var.subscription_id)}/")
      error_message = "virtual_hub_id must belong to subscription_id."
    }

    precondition {
      condition     = trimspace(var.customer_prefix) != ""
      error_message = "customer_prefix must not be empty."
    }
  }
}
