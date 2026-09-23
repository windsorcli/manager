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
| [keys](keys/) | Key material Manager's services generate and hold in Terraform state. |
| [keys/signing](keys/signing/) | Generates an ECDSA signing key held in Terraform state. |
| [object-store](object-store/) | S3-compatible bucket storage shared by every bucket-backed registry (Image Factory, Harbor). |
| [object-store/aws](object-store/aws/) | Creates S3 buckets with encryption, public access blocked, and Windsor tags. |
| [object-store/hetzner](object-store/hetzner/) | Creates buckets in Hetzner Object Storage. |
| [provisioning](provisioning/) | Terraform state Omni's provisioning capability needs outside the cluster. |
| [provisioning/omni](provisioning/omni/) | Generates Omni's config.account.id and holds an inactive etcd backup S3 config. |
<!-- END_INDEX -->
