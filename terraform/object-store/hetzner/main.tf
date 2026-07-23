# The object-store/hetzner module creates buckets in Hetzner Object Storage, which speaks
# S3 and is driven here through the AWS provider pointed at a location endpoint. Hetzner
# issues S3 credentials from the console only, so keys are inputs rather than resources.
#
# No default_tags: Hetzner does not implement PutBucketTagging, and provider-level tags
# would make every apply fail. Ownership is carried in the bucket name prefix instead.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }
  }
}

provider "aws" {
  access_key                  = var.access_key
  secret_key                  = var.secret_key
  region                      = var.location
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = local.endpoint
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  endpoint = "https://${var.location}.your-objectstorage.com"
}

# =============================================================================
# Buckets
# =============================================================================

resource "aws_s3_bucket" "this" {
  # Hetzner Object Storage implements the S3 API, not AWS's surrounding services: there is
  # no KMS, no cross-region replication, no access-logging target, and no public-access
  # block API. The checks below assume all four exist.
  # checkov:skip=CKV_AWS_145:Hetzner has no KMS; server-side encryption is AES256 or nothing
  # checkov:skip=CKV_AWS_144:Hetzner has no cross-region replication
  # checkov:skip=CKV_AWS_18:Hetzner has no access-logging target
  # checkov:skip=CKV2_AWS_6:Hetzner has no public access block API; buckets are private by default
  # checkov:skip=CKV_AWS_21:Versioning is off deliberately; these hold rebuildable artifacts
  # checkov:skip=CKV2_AWS_61:A cache needs no lifecycle rules; the factory rewrites what it needs
  # checkov:skip=CKV2_AWS_62:Nothing consumes bucket events
  for_each      = toset(var.buckets)
  bucket        = each.value
  force_destroy = var.force_destroy
}
