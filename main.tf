resource "azurerm_resource_group" "main" {
  name     = "portfolio-rg"
  location = "chilecentral"
}

resource "azurerm_virtual_network" "main" {
  name                = "portfolio-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name

    tags = {
        Name = "Portfolio-vnet"
    }
}

resource "azurerm_subnet" "public" {
  name                 = "portfolio-public-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
  depends_on = [azurerm_virtual_network.main]
}

resource "azurerm_subnet" "private" {
  name                 = "portfolio-private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  depends_on = [azurerm_subnet.public]
}
resource "azurerm_network_security_group" "web" {
  name                = "portfolio-web-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "201.241.101.159/32"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_public_ip" "web" {
  name                = "portfolio-web-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"

  tags = {
    Name = "Portfolio-web-ip"
  }
}

resource "azurerm_network_interface" "web" {
  name                = "portfolio-web-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web.id
  }
}
resource "azurerm_linux_virtual_machine" "web" {
  name                = "portfolio-web-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2ats_v2"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.web.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("portfolio-azure-key.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "Ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  custom_data = filebase64("custom_data.sh")
  tags = {
    Name = "Portfolio-web-vm"
  }
}

resource "random_string"  "storage_suffix" {
  length  = 6
  special = false
  upper  = false
}

resource "azurerm_storage_account" "assets" {
  name                     = "portfoliostorage${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  allow_nested_items_to_be_public = false

  tags = {
    Name = "Portfolio-storage"
  }
}
resource "azurerm_storage_container" "assets" {
  name                  = "static-assets"
  storage_account_id  = azurerm_storage_account.assets.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "sample_asset" {
  name                   = "hello.txt"
  storage_account_name   = azurerm_storage_account.assets.name
  storage_container_name = azurerm_storage_container.assets.name
  type                   = "Block"
  source                 = "assets/hello.txt"
}