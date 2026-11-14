output "result" {
  description = "The generated password."
  value       = random_password.password.result
  sensitive   = true
}
