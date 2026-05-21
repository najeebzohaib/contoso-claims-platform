resource "azurerm_public_ip" "bastion" {
  name                = "pip-${var.name}-bastion"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  name                = "bas-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # Standard SKU enables native client support, file copy, tunneling
  tunneling_enabled    = var.sku == "Standard" ? true : false
  file_copy_enabled    = var.sku == "Standard" ? true : false
  copy_paste_enabled   = true
  ip_connect_enabled   = var.sku == "Standard" ? true : false
  shareable_link_enabled = false

  ip_configuration {
    name                 = "bas-ipconfig"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = var.tags
}
