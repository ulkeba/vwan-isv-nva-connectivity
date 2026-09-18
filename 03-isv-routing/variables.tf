variable "location" {
  description = "Azure region for the route table."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing ISV resource group."
  type        = string
}

variable "route_table_name" {
  description = "Name of the customer-specific ISV route table."
  type        = string
}

variable "route_name" {
  description = "Name of the route to the customer network."
  type        = string
}
