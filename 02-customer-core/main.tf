locals {
  network_prefix  = "${var.customer_prefix}-network"
  workload_prefix = "${var.customer_prefix}-workload"
  bastion_prefix  = "${var.customer_prefix}-bastion"
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

resource "azurerm_virtual_wan" "customer" {
  name                = "${local.network_prefix}-vwan"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  type                = "Standard"
}

resource "azurerm_virtual_hub" "customer" {
  name                = "${local.network_prefix}-vhub"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
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
  name                = "${local.network_prefix}-vnet"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space       = [var.customer_virtual_network_address_space]
}

resource "azurerm_subnet" "workload" {
  name                 = "${local.network_prefix}-workload-snet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.customer.name
  address_prefixes     = [var.customer_workload_subnet_prefix]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.customer.name
  address_prefixes     = [var.customer_bastion_subnet_prefix]
}

resource "azurerm_network_security_group" "workload" {
  name                = "${local.network_prefix}-workload-nsg"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location

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

resource "azurerm_network_security_group" "bastion" {
  name                = "${local.network_prefix}-bastion-nsg"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location

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

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

module "customer_workload_vm" {
  source = "../modules/linux-test-vm"

  name                      = "${local.workload_prefix}-vm"
  location                  = azurerm_resource_group.workload.location
  resource_group_name       = azurerm_resource_group.workload.name
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = null
  private_ip_address        = var.customer_workload_private_ip_address
  vm_size                   = var.customer_workload_vm_size
  admin_username            = var.customer_workload_admin_username
  ssh_public_key            = file(pathexpand(var.customer_workload_ssh_public_key_path))
  zone                      = var.customer_workload_zone
  custom_data               = file("${path.module}/../cloud-init/testing-tools.yaml")
}

resource "azurerm_public_ip" "bastion" {
  name                = "${local.bastion_prefix}-pip"
  resource_group_name = azurerm_resource_group.bastion.name
  location            = azurerm_resource_group.bastion.location
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_bastion_host" "customer" {
  name                = "${local.bastion_prefix}-bas"
  resource_group_name = azurerm_resource_group.bastion.name
  location            = azurerm_resource_group.bastion.location
  sku                 = "Standard"
  tunneling_enabled   = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  depends_on = [azurerm_subnet_network_security_group_association.bastion]
}

resource "azurerm_virtual_hub_connection" "customer_workload" {
  name                      = "${local.network_prefix}-workload-conn"
  virtual_hub_id            = azurerm_virtual_hub.customer.id
  remote_virtual_network_id = azurerm_virtual_network.customer.id
  internet_security_enabled = var.virtual_hub_deploy_firewall

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

resource "azurerm_firewall_policy" "customer" {
  count = var.virtual_hub_deploy_firewall ? 1 : 0

  name                     = "${local.network_prefix}-fw-policy"
  resource_group_name      = azurerm_resource_group.network.name
  location                 = azurerm_resource_group.network.location
  sku                      = "Standard"
  threat_intelligence_mode = "Off"
}

resource "azurerm_firewall_policy_rule_collection_group" "customer" {
  count = var.virtual_hub_deploy_firewall ? 1 : 0

  name               = "${local.network_prefix}-fw-rules"
  firewall_policy_id = azurerm_firewall_policy.customer[0].id
  priority           = 100

  network_rule_collection {
    name     = "allow-private-10"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "allow-10-to-10"
      protocols             = ["Any"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["10.0.0.0/8"]
      destination_ports     = ["*"]
    }
  }

  application_rule_collection {
    name     = "deny-facebook"
    priority = 200
    action   = "Deny"

    rule {
      name              = "deny-www-facebook-com"
      source_addresses  = ["10.0.0.0/8"]
      destination_fqdns = ["www.facebook.com"]

      protocols {
        type = "Http"
        port = 80
      }

      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  application_rule_collection {
    name     = "allow-web"
    priority = 300
    action   = "Allow"

    rule {
      name              = "allow-http-https"
      source_addresses  = ["10.0.0.0/8"]
      destination_fqdns = ["*"]

      protocols {
        type = "Http"
        port = 80
      }

      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

resource "azurerm_firewall" "customer" {
  count = var.virtual_hub_deploy_firewall ? 1 : 0

  name                = "${local.network_prefix}-fw"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  sku_name            = "AZFW_Hub"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.customer[0].id

  virtual_hub {
    virtual_hub_id  = azurerm_virtual_hub.customer.id
    public_ip_count = 1
  }

  timeouts {
    create = "120m"
    read   = "15m"
    update = "120m"
    delete = "120m"
  }

  depends_on = [azurerm_virtual_hub_connection.customer_workload]
}

resource "azurerm_virtual_hub_routing_intent" "customer_internet" {
  count = var.virtual_hub_deploy_firewall ? 1 : 0

  name           = "${local.network_prefix}-internet-routing-intent"
  virtual_hub_id = azurerm_virtual_hub.customer.id

  routing_policy {
    name         = "InternetTraffic"
    destinations = ["Internet"]
    next_hop     = azurerm_firewall.customer[0].id
  }

  timeouts {
    create = "120m"
    read   = "15m"
    update = "120m"
    delete = "120m"
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.customer]
}
