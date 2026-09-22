locals {
  network_prefix  = "${var.isv_prefix}-network"
  workload_prefix = "${var.isv_prefix}-workload"
  bastion_prefix  = "${var.isv_prefix}-bastion"
}

resource "azurerm_resource_group" "network" {
  name     = "${local.network_prefix}-rg"
  location = var.location

  depends_on = [terraform_data.input_validation]
}

resource "azurerm_resource_group" "workload" {
  name     = "${local.workload_prefix}-rg"
  location = var.location

  depends_on = [terraform_data.input_validation]
}

resource "azurerm_resource_group" "bastion" {
  name     = "${local.bastion_prefix}-rg"
  location = var.location

  depends_on = [terraform_data.input_validation]
}

resource "azurerm_virtual_network" "this" {
  name                = "${local.network_prefix}-vnet"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = [var.virtual_network_address_space]
}

resource "azurerm_subnet" "nva" {
  name                 = "${local.network_prefix}-nva-snet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.nva_subnet_address_prefix]
}

resource "azurerm_subnet" "workload" {
  name                 = "${local.network_prefix}-workload-snet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.workload_subnet_address_prefix]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

resource "azurerm_network_security_group" "nva" {
  name                = "${local.network_prefix}-nva-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

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
  name                = "${local.network_prefix}-workload-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

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

resource "azurerm_network_security_group" "bastion" {
  name                = "${local.network_prefix}-bastion-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowBastionHostCommunicationInbound"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowSshRdpOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowBastionHostCommunicationOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowHttpOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
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

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

resource "azurerm_public_ip" "bastion" {
  name                = "${local.bastion_prefix}-pip"
  location            = azurerm_resource_group.bastion.location
  resource_group_name = azurerm_resource_group.bastion.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_bastion_host" "this" {
  name                = "${local.bastion_prefix}-bas"
  location            = azurerm_resource_group.bastion.location
  resource_group_name = azurerm_resource_group.bastion.name
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  depends_on = [azurerm_subnet_network_security_group_association.bastion]
}

module "nva_cluster" {
  source = "../modules/linux-nva-cluster"

  name_prefix                 = "${local.network_prefix}-nva"
  location                    = azurerm_resource_group.network.location
  resource_group_name         = azurerm_resource_group.network.name
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

  name                      = "${local.workload_prefix}-vm"
  location                  = azurerm_resource_group.workload.location
  resource_group_name       = azurerm_resource_group.workload.name
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = null
  private_ip_address        = var.workload_vm_private_ip_address
  vm_size                   = var.workload_vm_size
  admin_username            = var.admin_username
  ssh_public_key            = file(pathexpand(var.ssh_public_key_path))
  zone                      = var.workload_vm_zone
  custom_data               = file("${path.module}/../cloud-init/testing-tools.yaml")
}
