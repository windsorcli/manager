output "endpoint" {
  description = "S3 endpoint URL for the configured location."
  value       = local.endpoint
}

output "region" {
  description = "Region string S3 clients should send. Hetzner uses the location name."
  value       = var.location
}

output "buckets" {
  description = "Created bucket names, keyed by the name requested."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}
