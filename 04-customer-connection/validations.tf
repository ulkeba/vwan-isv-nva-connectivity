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
      condition = alltrue(concat(
        [can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualHubs/[^/]+/hubRouteTables/[^/]+$", var.associated_route_table_id))],
        [for id in var.propagated_route_table_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualHubs/[^/]+/hubRouteTables/[^/]+$", id))]
      ))
      error_message = "Associated and propagated route table IDs must be complete Virtual Hub Route Table resource IDs."
    }

    precondition {
      condition = alltrue(concat(
        [startswith(lower(var.associated_route_table_id), "${lower(var.virtual_hub_id)}/hubroutetables/")],
        [for id in var.propagated_route_table_ids : startswith(lower(id), "${lower(var.virtual_hub_id)}/hubroutetables/")]
      ))
      error_message = "Associated and propagated route tables must belong to virtual_hub_id."
    }

    precondition {
      condition     = startswith(lower(var.virtual_hub_id), "/subscriptions/${lower(var.subscription_id)}/")
      error_message = "virtual_hub_id must belong to subscription_id."
    }

    precondition {
      condition     = length(var.propagated_route_table_ids) > 0 && length(var.propagated_route_table_labels) > 0 && alltrue([for label in var.propagated_route_table_labels : trimspace(label) != ""])
      error_message = "At least one propagated route table ID and one non-empty label are required."
    }

    precondition {
      condition     = trimspace(var.isv_hub_connection_name) != "" && trimspace(var.static_route_name) != ""
      error_message = "Connection and static route names must not be empty."
    }
  }
}
