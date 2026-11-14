---
title: secrets/password
description: Generates a random alphanumeric password held in Terraform state.
---

# secrets/password

Generates a random alphanumeric password and keeps it in state, so every apply returns
the same value. The registry facet uses it as Harbor's initial admin password when
`registry.harbor.admin_password` is unset outside dev mode.

Consumed through `terraform_output("harbor-admin-password", "result")`. Read the value
back from the `harbor-admin-password` Secret in the `registry` namespace.

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
| [random_password.password](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_length"></a> [length](#input\_length) | Number of characters in the password. | `number` | `32` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_result"></a> [result](#output\_result) | The generated password. |
<!-- END_TF_DOCS -->
