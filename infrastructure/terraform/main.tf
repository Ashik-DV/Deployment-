locals {
  name = var.project_name
  tags = {
    project     = "blue-green-aks-lab"
    environment = "learning"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.name}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.0.0/24"]
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_container_registry" "main" {
  name                = "${local.name}acr${substr(replace(azurerm_resource_group.main.location, " ", ""), 0, 6)}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${local.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.name}-k8s"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "system"
    vm_size             = var.node_vm_size
    node_count          = var.system_node_count
    vnet_subnet_id      = azurerm_subnet.aks.id
    type                = "VirtualMachineScaleSets"
    auto_scaling_enabled = false
    node_labels = {
      "workload-tier" = "system"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    load_balancer_sku   = "standard"
    service_cidr        = "10.30.0.0/16"
    dns_service_ip      = "10.30.0.10"
  }

  role_based_access_control_enabled = true
  tags = local.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "blue" {
  name                  = "bluepool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size
  node_count            = var.workload_node_count
  mode                  = "User"
  vnet_subnet_id        = azurerm_subnet.aks.id
  node_labels = {
    "workload" = "blue"
    "release"  = "blue"
  }
  node_taints = ["workload=blue:NoSchedule"]
  tags = local.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "green" {
  name                  = "greenpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size
  node_count            = var.workload_node_count
  mode                  = "User"
  vnet_subnet_id        = azurerm_subnet.aks.id
  node_labels = {
    "workload" = "green"
    "release"  = "green"
  }
  node_taints = ["workload=green:NoSchedule"]
  tags = local.tags
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

resource "azurerm_public_ip" "appgw" {
  name                = "pip-${local.name}-appgw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-${local.name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name         = "kong-backend-pool"
    ip_addresses = [var.kong_internal_ip]
  }

  backend_http_settings {
    name                  = "kong-http-settings"
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "kong-health-probe"
  }

  probe {
    name                = "kong-health-probe"
    protocol            = "Http"
    path                = "/"
    host                = "bluegreen.example.com"
    interval            = 30
    timeout             = 10
    unhealthy_threshold = 3
    match {
      status_code = ["200-399"]
    }
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "route-to-kong"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "kong-backend-pool"
    backend_http_settings_name = "kong-http-settings"
    priority                   = 100
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}
