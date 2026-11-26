output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "application_gateway_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "kong_internal_ip" {
  value = var.kong_internal_ip
}
