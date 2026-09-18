resource "azurerm_resource_group" "customer" {
  name     = var.resource_group_name
  location = var.location

  depends_on = [terraform_data.input_validation]
}

resource "azurerm_virtual_wan" "customer" {
  name                = var.virtual_wan_name
  resource_group_name = azurerm_resource_group.customer.name
  location            = azurerm_resource_group.customer.location
  type                = "Standard"
}

resource "azurerm_virtual_hub" "customer" {
  name                = var.virtual_hub_name
  resource_group_name = azurerm_resource_group.customer.name
  location            = azurerm_resource_group.customer.location
  virtual_wan_id      = azurerm_virtual_wan.customer.id
  address_prefix      = var.virtual_hub_address_prefix
  sku                 = "Standard"

  timeouts {
    create = "120m"
    read   = "15m"
    update = "120m"
    delete = "120m"
  }
}

resource "azurerm_virtual_network" "customer" {
  name                = var.customer_virtual_network_name
  resource_group_name = azurerm_resource_group.customer.name
  location            = azurerm_resource_group.customer.location
  address_space       = [var.customer_virtual_network_address_space]
}

resource "azurerm_subnet" "workload" {
  name                 = var.customer_workload_subnet_name
  resource_group_name  = azurerm_resource_group.customer.name
  virtual_network_name = azurerm_virtual_network.customer.name
  address_prefixes     = [var.customer_workload_subnet_prefix]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.customer.name
  virtual_network_name = azurerm_virtual_network.customer.name
  address_prefixes     = [var.customer_bastion_subnet_prefix]
}

resource "azurerm_network_security_group" "workload" {
  name                = var.customer_workload_network_security_group_name
  resource_group_name = azurerm_resource_group.customer.name
  location            = azurerm_resource_group.customer.location

  security_rule {
    name                       = "AllowSshFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.customer_bastion_subnet_prefix
    destination_address_prefix = var.customer_workload_subnet_prefix
  }

  security_rule {
    name                       = "AllowTestTrafficFromIsv"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.isv_workload_address_prefix
    destination_address_prefix = var.customer_workload_subnet_prefix
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

module "customer_workload_vm" {
  source = "../modules/linux-test-vm"

  name                      = var.customer_workload_vm_name
  location                  = azurerm_resource_group.customer.location
  resource_group_name       = azurerm_resource_group.customer.name
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = null
  private_ip_address        = var.customer_workload_private_ip_address
  vm_size                   = var.customer_workload_vm_size
  admin_username            = var.customer_workload_admin_username
  ssh_public_key            = file(pathexpand(var.customer_workload_ssh_public_key_path))
  zone                      = var.customer_workload_zone
  custom_data               = null
}

resource "azurerm_public_ip" "bastion" {
  name                = var.customer_bastion_public_ip_name
  resource_group_name = azurerm_resource_group.customer.name
  location            = azurerm_resource_group.customer.location
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_bastion_host" "customer" {
  name                = var.customer_bastion_name
  resource_group_name = azurerm_resource_group.customer.name
  location            = azurerm_resource_group.customer.location
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

resource "azurerm_virtual_hub_connection" "customer_workload" {
  name                      = var.customer_workload_connection_name
  virtual_hub_id            = azurerm_virtual_hub.customer.id
  remote_virtual_network_id = azurerm_virtual_network.customer.id

  routing {
    associated_route_table_id = azurerm_virtual_hub.customer.default_route_table_id

    propagated_route_table {
      labels          = ["default"]
      route_table_ids = [azurerm_virtual_hub.customer.default_route_table_id]
    }
  }

  timeouts {
    create = "120m"
    read   = "15m"
    update = "120m"
    delete = "120m"
  }
}
