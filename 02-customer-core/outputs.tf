output "customer_resource_group" {
  description = "Customer resource group details."
  value = {
    id       = azurerm_resource_group.customer.id
    name     = azurerm_resource_group.customer.name
    location = azurerm_resource_group.customer.location
  }
}

output "customer_virtual_wan" {
  description = "Customer Virtual WAN details."
  value = {
    id   = azurerm_virtual_wan.customer.id
    name = azurerm_virtual_wan.customer.name
  }
}

output "customer_virtual_hub" {
  description = "Customer virtual hub details used by onboarding."
  value = {
    id                     = azurerm_virtual_hub.customer.id
    name                   = azurerm_virtual_hub.customer.name
    address_prefix         = azurerm_virtual_hub.customer.address_prefix
    default_route_table_id = azurerm_virtual_hub.customer.default_route_table_id
  }
}

output "customer_virtual_network" {
  description = "Customer virtual network details."
  value = {
    id             = azurerm_virtual_network.customer.id
    name           = azurerm_virtual_network.customer.name
    resource_group = azurerm_virtual_network.customer.resource_group_name
    location       = azurerm_virtual_network.customer.location
    address_spaces = azurerm_virtual_network.customer.address_space
  }
}

output "customer_workload_subnet" {
  description = "Customer workload subnet details."
  value = {
    id               = azurerm_subnet.workload.id
    name             = azurerm_subnet.workload.name
    address_prefixes = azurerm_subnet.workload.address_prefixes
  }
}

output "customer_workload_virtual_machine" {
  description = "Customer workload VM details used for verification."
  value = {
    id                 = module.customer_workload_vm.id
    name               = module.customer_workload_vm.name
    nic_id             = module.customer_workload_vm.nic_id
    private_ip_address = module.customer_workload_vm.private_ip_address
  }
}

output "customer_bastion" {
  description = "Customer Bastion details used for native SSH."
  value = {
    id       = azurerm_bastion_host.customer.id
    name     = azurerm_bastion_host.customer.name
    dns_name = azurerm_bastion_host.customer.dns_name
  }
}

output "customer_workload_connection" {
  description = "Customer workload virtual hub connection details."
  value = {
    id   = azurerm_virtual_hub_connection.customer_workload.id
    name = azurerm_virtual_hub_connection.customer_workload.name
  }
}
