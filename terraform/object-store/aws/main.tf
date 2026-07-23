# The object-store/aws module creates S3 buckets with the same interface as the other
# object-store implementations, so a facet can swap platforms without changing inputs.
# Credentials come from the ambient AWS provider chain (profile, environment, or IRSA)
# rather than being passed in.

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
  default_tags {
    tags = merge(
      var.tags,
      {
        ManagedBy        = "Terraform"
        WindsorContextID = var.context_id
      }
    )
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  endpoint = "https://s3.${var.region}.amazonaws.com"
}

# =============================================================================
# Buckets
# =============================================================================

resource "aws_s3_bucket" "this" {
  # These buckets hold rebuildable artifacts — boot assets the factory regenerates on a
  # cache miss — so the durability and audit controls these checks assume are not warranted.
  # checkov:skip=CKV_AWS_145:SSE-S3 is sufficient for rebuildable artifacts; KMS adds per-request cost and key policy surface
  # checkov:skip=CKV_AWS_144:Cross-region replication is not warranted for a cache
  # checkov:skip=CKV_AWS_18:Access logging would cost more than the data it audits
  # checkov:skip=CKV_AWS_21:Versioning is opt-in via var.versioning; a cache does not need history
  # checkov:skip=CKV2_AWS_61:A cache needs no lifecycle rules; the factory rewrites what it needs
  # checkov:skip=CKV2_AWS_62:Nothing consumes bucket events
  for_each      = toset(var.buckets)
  bucket        = each.value
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}
