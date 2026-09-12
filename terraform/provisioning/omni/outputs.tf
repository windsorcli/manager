output "id" {
  description = "UUID for Omni's config.account.id. Stable across applies."
  value       = random_uuid.account.result
}

# output "backup_destination_id" {
#   description = "Always etcd-backup-s3-conf; the configuration is a singleton."
#   value       = omni_etcd_backup_s3_config.backup.id
# }
