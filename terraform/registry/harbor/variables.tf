variable "admin_password_length" {
  description = "Number of characters in the generated admin password."
  type        = number
  default     = 32
  validation {
    condition     = var.admin_password_length >= 16 && var.admin_password_length <= 128
    error_message = "The length must be between 16 and 128."
  }
}
