variable "length" {
  description = "Number of characters in the password."
  type        = number
  default     = 32
  validation {
    condition     = var.length >= 16 && var.length <= 128
    error_message = "The length must be between 16 and 128."
  }
}
