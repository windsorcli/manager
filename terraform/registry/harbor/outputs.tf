output "admin_password" {
  description = "Harbor's initial admin password. Stable across applies."
  value       = random_password.admin.result
  sensitive   = true
}
