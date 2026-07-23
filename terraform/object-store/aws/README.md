---
title: object-store/aws
description: Creates S3 buckets with encryption, public access blocked, and Windsor tags.
---

# object-store/aws

Creates S3 buckets behind the same interface as the other object-store implementations, so
a facet can switch platforms without changing inputs.

Buckets get SSE-S3 encryption, a public access block, and `ManagedBy` / `WindsorContextID`
tags through the provider's `default_tags`. `context_id` is injected by Windsor as
`TF_VAR_context_id` and is not passed as a component input. Versioning is off by default and `force_destroy`
is on: these hold rebuildable artifacts, so history is cost without benefit and a non-empty
bucket should not block teardown.

Credentials come from the ambient AWS provider chain rather than being passed in.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.52.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.52.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/6.52.0/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/6.52.0/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/6.52.0/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/6.52.0/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_buckets"></a> [buckets](#input\_buckets) | Bucket names to create. S3 bucket names are globally unique, so they need a context-unique prefix. | `list(string)` | `[]` | no |
| <a name="input_context_id"></a> [context\_id](#input\_context\_id) | Context ID for the resources | `string` | `null` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Delete remaining objects, including all noncurrent versions, when the bucket is destroyed. On by default: these buckets hold rebuildable artifacts, and a non-empty or versioned bucket otherwise blocks teardown. | `bool` | `true` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region hosting the buckets. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to resources (default is empty). | `map(string)` | `{}` | no |
| <a name="input_versioning"></a> [versioning](#input\_versioning) | Keep object versions. Off by default: a cache of rebuildable artifacts does not need history, and versions accrue cost. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_buckets"></a> [buckets](#output\_buckets) | Created bucket names, keyed by the name requested. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | S3 endpoint URL for the configured region. |
| <a name="output_region"></a> [region](#output\_region) | Region string S3 clients should send. |
<!-- END_TF_DOCS -->