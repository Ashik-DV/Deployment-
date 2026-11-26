variable "project_name" {
  description = "Short project prefix used in Azure resource names."
  type        = string
  default     = "bgdemo"
}

variable "location" {
  description = "Azure region. Confirm AKS quota and service availability before applying."
  type        = string
  default     = "malaysiawest"
}

variable "node_vm_size" {
  description = "VM size for system, blue and green pools. Must have quota in the selected region."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "system_node_count" {
  type    = number
  default = 1
}

variable "workload_node_count" {
  description = "Initial node count for each Blue and Green pool."
  type        = number
  default     = 1
}

variable "kong_internal_ip" {
  description = "Static private IP reserved for Kong's internal LoadBalancer Service."
  type        = string
  default     = "10.20.1.10"
}

variable "kubernetes_version" {
  description = "Optional AKS Kubernetes version. Null selects the Azure-supported default."
  type        = string
  default     = null
}
