output "id" {
  description = "UUID for Omni's config.account.id. Stable across applies."
  value       = random_uuid.account.result
}
