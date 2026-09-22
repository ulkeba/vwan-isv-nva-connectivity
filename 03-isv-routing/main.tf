locals {
  network_prefix = "${var.isv_prefix}-network"
}

resource "azurerm_route_table" "this" {
  name                          = "${local.network_prefix}-customer-rt"
  location                      = var.location
  resource_group_name           = "${local.network_prefix}-rg"
  bgp_route_propagation_enabled = true
}

resource "azurerm_route" "customer" {
  name                   = "${local.network_prefix}-customer-route"
  resource_group_name    = "${local.network_prefix}-rg"
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = var.customer_address_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.nva_frontend_private_ip_address
}

resource "azurerm_subnet_route_table_association" "workload" {
  subnet_id      = var.isv_workload_subnet_id
  route_table_id = azurerm_route_table.this.id
}
