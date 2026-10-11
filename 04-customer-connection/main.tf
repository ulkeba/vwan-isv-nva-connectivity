locals {
  network_prefix = "${var.customer_prefix}-network"
}

resource "azurerm_virtual_hub_connection" "isv" {
  name                      = "${local.network_prefix}-isv-conn"
  virtual_hub_id            = var.virtual_hub_id
  remote_virtual_network_id = var.isv_virtual_network_id

  routing {
    associated_route_table_id = var.associated_route_table_id

    # This property corresponds to the option "Bypass Next Hop IP for workloads within this VNet" in the Azure portal.
    # "Contains": corresponds to "No"
    # "Equal": corresponds to "Yes"
    static_vnet_local_route_override_criteria = "Contains"

    # This property corresponds to the option "Propagate static route" in the Azure portal.
    static_vnet_propagate_static_routes_enabled = true

    static_vnet_route {
      name                = "${local.network_prefix}-isv-workload-route"
      address_prefixes    = [var.isv_workload_address_prefix]
      next_hop_ip_address = var.nva_load_balancer_frontend_ip_address
    }
  }

  timeouts {
    create = "120m"
    read   = "15m"
    update = "120m"
    delete = "120m"
  }

  depends_on = [terraform_data.input_validation]
}
