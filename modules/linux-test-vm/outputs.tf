output "id" {
  description = "Resource ID of the Linux test VM."
  value       = azurerm_linux_virtual_machine.this.id
}

output "name" {
  description = "Name of the Linux test VM."
  value       = azurerm_linux_virtual_machine.this.name
}

output "nic_id" {
  description = "Resource ID of the Linux test VM NIC."
  value       = azurerm_network_interface.this.id
}

output "private_ip_address" {
  description = "Private IPv4 address of the Linux test VM."
  value       = azurerm_network_interface.this.private_ip_address
}

output "virtual_machine" {
  description = "Structured Linux test VM details."
  value = {
    id                  = azurerm_linux_virtual_machine.this.id
    name                = azurerm_linux_virtual_machine.this.name
    resource_group_name = azurerm_linux_virtual_machine.this.resource_group_name
    location            = azurerm_linux_virtual_machine.this.location
    zone                = azurerm_linux_virtual_machine.this.zone
    nic_id              = azurerm_network_interface.this.id
    private_ip_address  = azurerm_network_interface.this.private_ip_address
  }
}
