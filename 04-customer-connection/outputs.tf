output "isv_hub_connection" {
  description = "ISV virtual hub connection and configured routing contract."
  value = {
    id                        = azurerm_virtual_hub_connection.isv.id
    name                      = azurerm_virtual_hub_connection.isv.name
    associated_route_table_id = var.associated_route_table_id
    static_route = {
      name                = "${local.network_prefix}-isv-workload-route"
      address_prefixes    = [var.isv_workload_address_prefix]
      next_hop_ip_address = var.nva_load_balancer_frontend_ip_address
    }
  }
}
