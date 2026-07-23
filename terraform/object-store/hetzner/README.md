---
title: object-store/hetzner
description: Creates buckets in Hetzner Object Storage.
---

# object-store/hetzner

Creates buckets in Hetzner Object Storage, which speaks S3 and is driven here through the
AWS provider aimed at a location endpoint.

Object Storage runs in `fsn1`, `nbg1`, and `hel1` only — not in the `ash`, `hil`, or `sin`
compute locations — and the module rejects the others rather than failing at apply. S3
credentials are created in the Hetzner console; there is no API for them, so they are
inputs.

Hetzner omits several bucket-level S3 APIs by design, including tagging, ACLs, access
logging, and replication. There is no `default_tags` block for that reason: provider-level
tags would make every apply fail. Buckets carry ownership in their name prefix instead.

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

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_key"></a> [access\_key](#input\_access\_key) | S3 access key for the Hetzner project. Generated in the Hetzner console; there is no API to create one. | `string` | n/a | yes |
| <a name="input_buckets"></a> [buckets](#input\_buckets) | Bucket names to create. Names are shared across the whole Hetzner project, so they need a context-unique prefix. | `list(string)` | `[]` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Delete remaining objects when the bucket is destroyed. On by default: these buckets hold rebuildable artifacts, and a non-empty bucket otherwise blocks teardown. | `bool` | `true` | no |
| <a name="input_location"></a> [location](#input\_location) | Hetzner location hosting the buckets. Object Storage runs in fsn1, nbg1, and hel1 only, not in the ash, hil, or sin compute locations. | `string` | `"fsn1"` | no |
| <a name="input_secret_key"></a> [secret\_key](#input\_secret\_key) | S3 secret key paired with access\_key. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_buckets"></a> [buckets](#output\_buckets) | Created bucket names, keyed by the name requested. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | S3 endpoint URL for the configured location. |
| <a name="output_region"></a> [region](#output\_region) | Region string S3 clients should send. Hetzner uses the location name. |
<!-- END_TF_DOCS -->