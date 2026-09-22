variable "subscription_id" {
  description = "Customer Azure subscription ID containing the virtual hub."
  type        = string
}

variable "customer_prefix" {
  description = "Prefix used to derive customer network resource names."
  type        = string
  default     = "fd-customer"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.customer_prefix))
    error_message = "customer_prefix must contain only lowercase letters, numbers, and internal hyphens."
  }
}

variable "virtual_hub_id" {
  description = "Resource ID of the customer-owned virtual hub."
  type        = string
}

variable "isv_virtual_network_id" {
  description = "Resource ID of the ISV-owned virtual network."
  type        = string
}

variable "isv_workload_address_prefix" {
  description = "ISV workload CIDR routed through the NVA."
  type        = string
}

variable "nva_load_balancer_frontend_ip_address" {
  description = "Private frontend IP of the ISV NVA load balancer."
  type        = string
}

variable "associated_route_table_id" {
  description = "Hub route table ID associated with the ISV connection."
  type        = string
}

variable "propagated_route_table_ids" {
  description = "Hub route table IDs receiving routes from the ISV connection."
  type        = list(string)
}

variable "propagated_route_table_labels" {
  description = "Hub route table labels receiving routes from the ISV connection."
  type        = list(string)
}
