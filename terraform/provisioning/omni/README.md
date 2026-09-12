---
title: provisioning/omni
description: Generates Omni's config.account.id and holds an inactive etcd backup S3 config.
---

# provisioning/omni

Generates a UUID for Omni's `config.account.id`. The value stays in Terraform state, so
every apply returns the same UUID. The Omni chart needs this ID to install, and the ID
must stay fixed for the life of the installation.

Consumed through `terraform_output("omni-account", "id")`.

## Etcd backup destination (not active yet)

This module also holds Omni's `EtcdBackupS3Config` resource, commented out. Two reasons:

- `terraform-provider-omni` merged the `omni_etcd_backup_s3_config` resource, but has
  not released it yet. The latest release, `v0.1.0-alpha.3`, predates the merge.
- The resource configures a live Omni instance. Terraform always runs before the
  blueprint that deploys Omni, so this needs a later, separate apply. Omni also has no
  non-interactive login, so that apply needs an Admin-role service account key an
  operator creates by hand (`omnictl serviceaccount create --use-user-role=false
  --role=Admin omni-backup`).

The resource stays in this module, not its own, because Terraform checks a resource's
type against the provider schema at plan time regardless of `count`. A live reference
to it anywhere would break this module's own tests, too, against a provider release
that does not support it yet.

To activate it later: uncomment the resource, wire it into `addon-provisioning.yaml`'s
`terraform:` block, and bump the pinned provider version.

The backup *bucket* has no such blocker. `omni-backup-object-store` provisions it today,
on either `object-store/hetzner` or `object-store/aws`. Wiring Omni to that bucket will
likely stay Hetzner-only even after the provider ships: Omni needs its own static S3
credentials, and only Hetzner hands those out today. AWS bucket creation uses ambient
credentials, which Omni's backend cannot authenticate with.

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
| [random_uuid.account](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/uuid) | resource |

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | UUID for Omni's config.account.id. Stable across applies. |
<!-- END_TF_DOCS -->
