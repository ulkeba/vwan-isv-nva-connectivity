resource "azurerm_route_table" "this" {
  name                          = var.route_table_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
}

resource "azurerm_route" "customer" {
  name                   = var.route_name
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = var.customer_address_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.nva_frontend_private_ip_address
}

resource "azurerm_subnet_route_table_association" "workload" {
  subnet_id      = var.isv_workload_subnet_id
  route_table_id = azurerm_route_table.this.id
}
