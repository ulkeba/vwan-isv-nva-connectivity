resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  depends_on = [terraform_data.input_validation]
}

resource "azurerm_virtual_network" "this" {
  name                = var.virtual_network_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.virtual_network_address_space]
}

resource "azurerm_subnet" "nva" {
  name                 = var.nva_subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.nva_subnet_address_prefix]
}

resource "azurerm_subnet" "workload" {
  name                 = var.workload_subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.workload_subnet_address_prefix]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

resource "azurerm_network_security_group" "nva" {
  name                = var.nva_network_security_group_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowSshFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_address_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerProbe"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.health_probe_port)
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowCustomerForwarding"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.customer_address_prefix
    destination_address_prefix = var.workload_subnet_address_prefix
  }

  security_rule {
    name                       = "AllowWorkloadForwarding"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.workload_subnet_address_prefix
    destination_address_prefix = var.customer_address_prefix
  }
}

resource "azurerm_network_security_group" "workload" {
  name                = var.workload_network_security_group_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowSshFromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_address_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowCustomerTestTraffic"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.customer_address_prefix
    destination_address_prefix = var.workload_subnet_address_prefix
  }
}

resource "azurerm_subnet_network_security_group_association" "nva" {
  subnet_id                 = azurerm_subnet.nva.id
  network_security_group_id = azurerm_network_security_group.nva.id
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_public_ip" "bastion" {
  name                = var.bastion_public_ip_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_bastion_host" "this" {
  name                = var.bastion_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

module "nva_cluster" {
  source = "../modules/linux-nva-cluster"

  name_prefix                 = var.nva_name_prefix
  location                    = azurerm_resource_group.this.location
  resource_group_name         = azurerm_resource_group.this.name
  subnet_id                   = azurerm_subnet.nva.id
  network_security_group_id   = null
  vm_size                     = var.nva_vm_size
  admin_username              = var.admin_username
  ssh_public_key              = file(pathexpand(var.ssh_public_key_path))
  zones                       = var.nva_zones
  frontend_private_ip_address = var.nva_frontend_private_ip_address
  customer_address_prefix     = var.customer_address_prefix
  isv_workload_address_prefix = var.workload_subnet_address_prefix
  health_probe_port           = var.health_probe_port
}

module "workload_vm" {
  source = "../modules/linux-test-vm"

  name                      = var.workload_vm_name
  location                  = azurerm_resource_group.this.location
  resource_group_name       = azurerm_resource_group.this.name
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = null
  private_ip_address        = var.workload_vm_private_ip_address
  vm_size                   = var.workload_vm_size
  admin_username            = var.admin_username
  ssh_public_key            = file(pathexpand(var.ssh_public_key_path))
  zone                      = var.workload_vm_zone
  custom_data               = null
}
