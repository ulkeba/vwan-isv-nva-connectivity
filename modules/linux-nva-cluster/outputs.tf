output "load_balancer_id" {
  description = "Resource ID of the internal Standard Load Balancer."
  value       = azurerm_lb.this.id
}

output "frontend_ip_address" {
  description = "Private frontend IP address used as the stable NVA next hop."
  value       = var.frontend_private_ip_address
}

output "virtual_machines" {
  description = "NVA VM details keyed by VM name."
  value = {
    for key, instance in local.instances : instance.name => {
      id         = azurerm_linux_virtual_machine.this[key].id
      name       = azurerm_linux_virtual_machine.this[key].name
      zone       = azurerm_linux_virtual_machine.this[key].zone
      nic_id     = azurerm_network_interface.this[key].id
      private_ip = azurerm_network_interface.this[key].private_ip_address
      public_ip  = azurerm_public_ip.this[key].ip_address
    }
  }
}

output "health_probe" {
  description = "TCP health-probe details."
  value = {
    id   = azurerm_lb_probe.this.id
    port = var.health_probe_port
  }
}
