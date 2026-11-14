---
title: Terraform module reference
description: Reference index for the Terraform modules in this blueprint.
---

# terraform/

Reference index for the Terraform modules in this blueprint. See
[STYLE.md](STYLE.md) for authoring conventions.

## Modules

<!-- BEGIN_INDEX -->

| Path | Purpose |
|---|---|
| [keys/signing](keys/signing/) | Generates an ECDSA signing key held in Terraform state. |
| [object-store/aws](object-store/aws/) | Creates S3 buckets with encryption, public access blocked, and Windsor tags. |
| [object-store/hetzner](object-store/hetzner/) | Creates buckets in Hetzner Object Storage. |
| [provisioning/omni](provisioning/omni/) | Generates Omni's config.account.id and holds an inactive etcd backup S3 config. |
| [registry/harbor](registry/harbor/) | Generates Harbor's initial admin password and holds it in Terraform state. |
<!-- END_INDEX -->
