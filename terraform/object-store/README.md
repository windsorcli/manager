---
title: object-store
description: S3-compatible bucket storage shared by every bucket-backed registry (Image Factory, Harbor).
stack_backing: S3 buckets for Image Factory & Harbor
---

Resolves the object storage backend shared by every bucket-backed registry —
Image Factory's cache and Harbor's own bucket, each with its own path and
destroy semantics. Driver variants: [`aws`](aws), [`hetzner`](hetzner).

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [aws](aws/) — Creates S3 buckets with encryption, public access blocked, and Windsor tags.
- [hetzner](hetzner/) — Creates buckets in Hetzner Object Storage.
<!-- END_TERRAFORM_MODULES -->
