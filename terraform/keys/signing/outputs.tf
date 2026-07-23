output "private_key_pem" {
  description = "PEM-encoded private key. Consumed as the image factory cache signing key."
  value       = tls_private_key.signing.private_key_pem
  sensitive   = true
}

output "public_key_pem" {
  description = "PEM-encoded public key, for verifying signatures produced with this key."
  value       = tls_private_key.signing.public_key_pem
}
