resource "azurerm_virtual_hub_connection" "isv" {
  name                      = var.isv_hub_connection_name
  virtual_hub_id            = var.virtual_hub_id
  remote_virtual_network_id = var.isv_virtual_network_id

  routing {
    associated_route_table_id                   = var.associated_route_table_id
    static_vnet_local_route_override_criteria   = "Contains"
    static_vnet_propagate_static_routes_enabled = true

    propagated_route_table {
      labels          = var.propagated_route_table_labels
      route_table_ids = var.propagated_route_table_ids
    }

    static_vnet_route {
      name                = var.static_route_name
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
