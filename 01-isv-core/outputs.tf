output "isv_resource_groups" {
  description = "ISV resource groups by role."
  value = {
    network = {
      id   = azurerm_resource_group.network.id
      name = azurerm_resource_group.network.name
    }
    workload = {
      id   = azurerm_resource_group.workload.id
      name = azurerm_resource_group.workload.name
    }
    bastion = {
      id   = azurerm_resource_group.bastion.id
      name = azurerm_resource_group.bastion.name
    }
  }
}

output "isv_virtual_network" {
  description = "ISV virtual network details for onboarding."
  value = {
    id             = azurerm_virtual_network.this.id
    name           = azurerm_virtual_network.this.name
    resource_group = azurerm_virtual_network.this.resource_group_name
    location       = azurerm_virtual_network.this.location
    address_spaces = azurerm_virtual_network.this.address_space
  }
}

output "isv_workload_subnet" {
  description = "ISV workload subnet details required by the routing deployment."
  value = {
    id               = azurerm_subnet.workload.id
    name             = azurerm_subnet.workload.name
    address_prefixes = azurerm_subnet.workload.address_prefixes
  }
}

output "nva_load_balancer" {
  description = "NVA load balancer details required by onboarding deployments."
  value = {
    id          = module.nva_cluster.load_balancer_id
    frontend_ip = module.nva_cluster.frontend_ip_address
  }
}

output "nva_virtual_machines" {
  description = "NVA virtual machine details used during failover verification."
  value       = module.nva_cluster.virtual_machines
}

output "isv_workload_virtual_machine" {
  description = "ISV workload VM connection details."
  value = {
    id                 = module.workload_vm.id
    name               = module.workload_vm.name
    nic_id             = module.workload_vm.nic_id
    private_ip_address = module.workload_vm.private_ip_address
  }
}

output "isv_bastion" {
  description = "Azure Bastion details used for native-client SSH."
  value = {
    id             = azurerm_bastion_host.this.id
    name           = azurerm_bastion_host.this.name
    resource_group = azurerm_bastion_host.this.resource_group_name
    dns_name       = azurerm_bastion_host.this.dns_name
  }
}
