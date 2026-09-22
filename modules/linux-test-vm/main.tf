resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.private_ip_address == null ? "Dynamic" : "Static"
    private_ip_address            = var.private_ip_address
    primary                       = true
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  count = var.network_security_group_id == null ? 0 : 1

  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = var.network_security_group_id
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  zone                            = var.zone
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.this.id]
  custom_data                     = var.custom_data == null ? null : base64encode(var.custom_data)

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "${var.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.source_image_reference.publisher
    offer     = var.source_image_reference.offer
    sku       = var.source_image_reference.sku
    version   = var.source_image_reference.version
  }

  depends_on = [azurerm_network_interface_security_group_association.this]
}

resource "azurerm_virtual_machine_extension" "cloud_init_health" {
  count = var.custom_data == null ? 0 : 1

  name                       = "${var.name}-cloud-init-health-vmext"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "/bin/sh -c 'cloud-init status --wait --long && command -v nc netstat tcpdump ping python3 >/dev/null'"
  })
}
