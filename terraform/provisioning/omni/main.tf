# The provisioning/omni module generates Omni's config.account.id and holds it in
# state. The chart needs this ID to install. The ID must stay fixed for the life of
# the installation, so every apply must return the same UUID.

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
    # omni = {
    #   source  = "siderolabs/omni"
    #   version = "0.1.0-alpha.3"
    # }
  }
}

# provider "omni" {
#   endpoint                 = var.backup_endpoint
#   service_account_key      = var.backup_service_account_key
#   insecure_skip_tls_verify = var.backup_insecure_skip_tls_verify
# }

# =============================================================================
# Account ID
# =============================================================================

resource "random_uuid" "account" {}

# =============================================================================
# Etcd Backup Destination
# =============================================================================
# Commented out: needs a terraform-provider-omni release that does not exist yet.
# See this module's README.

# resource "omni_etcd_backup_s3_config" "backup" {
#   bucket            = var.backup_bucket
#   region            = var.backup_region != "" ? var.backup_region : null
#   endpoint          = var.backup_s3_endpoint != "" ? var.backup_s3_endpoint : null
#   access_key_id     = var.backup_access_key_id
#   secret_access_key = var.backup_secret_access_key
# }
