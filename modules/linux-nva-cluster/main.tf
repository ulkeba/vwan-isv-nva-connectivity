locals {
  instances = {
    for index, zone in var.zones : tostring(index) => {
      name = "${var.name_prefix}-${index + 1}"
      zone = zone
    }
  }

  cloud_init = templatefile("${path.module}/../../nva/cloud-init.yaml.tftpl", {
    customer_workload_cidr    = var.customer_address_prefix
    isv_workload_cidr         = var.isv_workload_address_prefix
    probe_port                = var.health_probe_port
    forwarding_health_service = file("${path.module}/../../nva/forwarding-health.service")
    forwarding_health_socket = templatefile("${path.module}/../../nva/forwarding-health.socket", {
      probe_port = var.health_probe_port
    })
  })
}

resource "azurerm_lb" "this" {
  name                = "${var.name_prefix}-lb"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  sku_tier            = "Regional"

  frontend_ip_configuration {
    name                          = "${var.name_prefix}-frontend"
    subnet_id                     = var.subnet_id
    private_ip_address            = var.frontend_private_ip_address
    private_ip_address_allocation = "Static"
  }
}

resource "azurerm_lb_backend_address_pool" "this" {
  name            = "${var.name_prefix}-backend"
  loadbalancer_id = azurerm_lb.this.id
}

resource "azurerm_lb_probe" "this" {
  name                = "${var.name_prefix}-health"
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = "Tcp"
  port                = var.health_probe_port
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "ha_ports" {
  name                           = "${var.name_prefix}-ha-ports"
  loadbalancer_id                = azurerm_lb.this.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "${var.name_prefix}-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.this.id
  floating_ip_enabled            = true
  disable_outbound_snat          = true
}

resource "azurerm_network_interface" "this" {
  for_each = local.instances

  name                  = "${each.value.name}-nic"
  location              = var.location
  resource_group_name   = var.resource_group_name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  for_each = {
    for key, instance in local.instances : key => instance
    if var.network_security_group_id != null
  }

  network_interface_id      = azurerm_network_interface.this[each.key].id
  network_security_group_id = var.network_security_group_id
}

resource "azurerm_network_interface_backend_address_pool_association" "this" {
  for_each = local.instances

  network_interface_id    = azurerm_network_interface.this[each.key].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
}

resource "azurerm_linux_virtual_machine" "this" {
  for_each = local.instances

  name                            = each.value.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  zone                            = each.value.zone
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.this[each.key].id]
  custom_data                     = base64encode(local.cloud_init)

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "${each.value.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }

  depends_on = [
    azurerm_network_interface_backend_address_pool_association.this,
  ]
}

resource "azurerm_virtual_machine_extension" "cloud_init_health" {
  for_each = local.instances

  name                       = "${each.value.name}-cloud-init-health"
  virtual_machine_id         = azurerm_linux_virtual_machine.this[each.key].id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "/bin/sh -c 'cloud-init status --wait --long && test \"$(sysctl -n net.ipv4.ip_forward)\" = 1 && nft list counter inet nva_forward customer_to_isv >/dev/null && nft list counter inet nva_forward isv_to_customer >/dev/null && systemctl is-active --quiet forwarding-health.socket && /usr/local/bin/check-forwarding-health && systemctl is-active --quiet forwarding-health.service'"
  })
}
