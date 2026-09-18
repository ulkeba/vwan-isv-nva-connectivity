output "isv_route_table" {
  description = "Customer-specific ISV route table and route details."
  value = {
    id   = azurerm_route_table.this.id
    name = azurerm_route_table.this.name
    route = {
      id             = azurerm_route.customer.id
      name           = azurerm_route.customer.name
      address_prefix = azurerm_route.customer.address_prefix
      next_hop = {
        type       = azurerm_route.customer.next_hop_type
        ip_address = azurerm_route.customer.next_hop_in_ip_address
      }
    }
    associated_subnet_id = azurerm_subnet_route_table_association.workload.subnet_id
  }
}
