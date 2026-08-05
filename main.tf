resource "azurerm_resource_group" "main" {
  name     = "portfolio-rg"
  location = "eastus"
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
}

resource "azurerm_subnet" "private" {
  name                 = "portfolio-private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
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
  size                = "Standard_D2s_v3"
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