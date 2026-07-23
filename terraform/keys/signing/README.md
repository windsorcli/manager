---
title: keys/signing
description: Generates an ECDSA signing key held in Terraform state.
---

# keys/signing

Generates an ECDSA P-256 private key and keeps it in state, so every apply returns the
same key. The image factory signs cached boot assets with it and nodes verify downloads
against the matching public key, which makes rotation a breaking change: assets signed
with the previous key no longer verify.

Consumed through `terraform_output("image-factory-signing-key", "private_key_pem")`. The
facet skips this module when `addons.image_factory.cache_signing_key` is set.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | 4.1.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.1.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [tls_private_key.signing](https://registry.terraform.io/providers/hashicorp/tls/4.1.0/docs/resources/private_key) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_algorithm"></a> [algorithm](#input\_algorithm) | Key algorithm. The image factory expects ECDSA. | `string` | `"ECDSA"` | no |
| <a name="input_ecdsa_curve"></a> [ecdsa\_curve](#input\_ecdsa\_curve) | Curve used when algorithm is ECDSA. The image factory expects P256. | `string` | `"P256"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_private_key_pem"></a> [private\_key\_pem](#output\_private\_key\_pem) | PEM-encoded private key. Consumed as the image factory cache signing key. |
| <a name="output_public_key_pem"></a> [public\_key\_pem](#output\_public\_key\_pem) | PEM-encoded public key, for verifying signatures produced with this key. |
<!-- END_TF_DOCS -->