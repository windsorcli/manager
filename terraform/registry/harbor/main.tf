# The registry/harbor module generates Harbor's initial admin password and holds it in
# state, so every apply returns the same value.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

# =============================================================================
# Admin Password
# =============================================================================

# The random_password is an alphanumeric password with at least one upper, lower, and digit.
resource "random_password" "admin" {
  length      = var.admin_password_length
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}
