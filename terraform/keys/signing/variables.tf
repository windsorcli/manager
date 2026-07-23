variable "algorithm" {
  description = "Key algorithm. The image factory expects ECDSA."
  type        = string
  default     = "ECDSA"
  validation {
    condition     = contains(["ECDSA", "RSA"], var.algorithm)
    error_message = "The algorithm must be ECDSA or RSA."
  }
}

variable "ecdsa_curve" {
  description = "Curve used when algorithm is ECDSA. The image factory expects P256."
  type        = string
  default     = "P256"
  validation {
    condition     = contains(["P224", "P256", "P384", "P521"], var.ecdsa_curve)
    error_message = "The curve must be one of P224, P256, P384, P521."
  }
}
