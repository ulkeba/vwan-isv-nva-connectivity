variable "location" {
  description = "Azure region for the route table."
  type        = string
}

variable "isv_prefix" {
  description = "Prefix used to derive ISV network resource names."
  type        = string
  default     = "fd-isv"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.isv_prefix))
    error_message = "isv_prefix must contain only lowercase letters, numbers, and internal hyphens."
  }
}
