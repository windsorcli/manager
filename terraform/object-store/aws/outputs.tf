output "endpoint" {
  description = "S3 endpoint URL for the configured region."
  value       = local.endpoint
}

output "region" {
  description = "Region string S3 clients should send."
  value       = var.region
}

output "buckets" {
  description = "Created bucket names, keyed by the name requested."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}
