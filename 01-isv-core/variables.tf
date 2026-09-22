variable "location" {
  description = "Azure region for all ISV core resources."
  type        = string
}

variable "isv_prefix" {
  description = "Prefix used to derive all ISV resource names."
  type        = string
  default     = "fd-isv"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.isv_prefix))
    error_message = "isv_prefix must contain only lowercase letters, numbers, and internal hyphens."
  }
}

variable "nva_vm_size" {
  description = "Azure VM size for each NVA."
  type        = string
}

variable "workload_vm_size" {
  description = "Azure VM size for the workload test VM."
  type        = string
}
