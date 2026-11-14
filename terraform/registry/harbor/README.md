---
title: registry/harbor
description: Generates Harbor's initial admin password and holds it in Terraform state.
---

# registry/harbor

Generates Harbor's initial admin password and keeps it in state, so every apply returns
the same value. The registry facet skips this module in dev mode and when
`registry.harbor.admin_password` is set.

Consumed through `terraform_output("harbor", "admin_password")`. Read the value back
from the `harbor-admin-password` Secret in the `registry` namespace.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.9.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [random_password.admin](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_password_length"></a> [admin\_password\_length](#input\_admin\_password\_length) | Number of characters in the generated admin password. | `number` | `32` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_password"></a> [admin\_password](#output\_admin\_password) | Harbor's initial admin password. Stable across applies. |
<!-- END_TF_DOCS -->
