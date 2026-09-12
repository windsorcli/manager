# Etcd backup destination inputs. Commented out along with the resource in main.tf.
# See the README.

# variable "backup_endpoint" {
#   description = "Omni API endpoint, e.g. https://omni.example.com."
#   type        = string
#   validation {
#     condition     = can(regex("^https://", var.backup_endpoint))
#     error_message = "The endpoint must be an https:// URL."
#   }
# }
#
# variable "backup_service_account_key" {
#   description = "Base64-encoded Admin-role Omni service account key."
#   type        = string
#   sensitive   = true
#   validation {
#     condition     = length(var.backup_service_account_key) > 0
#     error_message = "The service account key must not be empty."
#   }
# }
#
# variable "backup_insecure_skip_tls_verify" {
#   description = "Skip TLS verification against the Omni endpoint. Dev-mode private CAs only."
#   type        = bool
#   default     = false
# }
#
# variable "backup_bucket" {
#   description = "S3 bucket backing Omni's etcd backups."
#   type        = string
#   validation {
#     condition     = length(var.backup_bucket) > 0
#     error_message = "The bucket must not be empty."
#   }
# }
#
# variable "backup_region" {
#   description = "Region of the bucket, e.g. us-east-1. Leave empty for region-less S3-compatible storage."
#   type        = string
#   default     = ""
# }
#
# variable "backup_s3_endpoint" {
#   description = "Custom S3 endpoint. Leave empty to use the AWS endpoint for the configured region."
#   type        = string
#   default     = ""
# }
#
# variable "backup_access_key_id" {
#   description = "Static S3 access key ID Omni's own backend authenticates with."
#   type        = string
#   sensitive   = true
#   validation {
#     condition     = length(var.backup_access_key_id) > 0
#     error_message = "The access key ID must not be empty."
#   }
# }
#
# variable "backup_secret_access_key" {
#   description = "Static S3 secret access key, paired with backup_access_key_id."
#   type        = string
#   sensitive   = true
#   validation {
#     condition     = length(var.backup_secret_access_key) > 0
#     error_message = "The secret access key must not be empty."
#   }
# }
