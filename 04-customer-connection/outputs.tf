output "isv_hub_connection" {
  description = "ISV virtual hub connection and configured routing contract."
  value = {
    id                            = azurerm_virtual_hub_connection.isv.id
    name                          = azurerm_virtual_hub_connection.isv.name
    associated_route_table_id     = var.associated_route_table_id
    propagated_route_table_ids    = var.propagated_route_table_ids
    propagated_route_table_labels = var.propagated_route_table_labels
    static_route = {
      name                = var.static_route_name
      address_prefixes    = [var.isv_workload_address_prefix]
      next_hop_ip_address = var.nva_load_balancer_frontend_ip_address
    }
  }
}
