output "vm_public_ip" {
  description = "Public Ip de la maquina virtual"
  value = azurerm_public_ip.web.ip_address
}