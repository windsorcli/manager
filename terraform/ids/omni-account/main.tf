# The ids/omni-account module generates Omni's config.account.id and holds it in
# state. The chart refuses to install without it, and Omni's own docs require it stay
# fixed for the lifetime of the installation, so the same UUID has to be returned on
# every apply.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}

# =============================================================================
# Account ID
# =============================================================================

resource "random_uuid" "account" {}
