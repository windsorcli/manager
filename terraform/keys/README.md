---
title: keys
description: Key material Manager's services generate and hold in Terraform state.
stack_backing: Image Factory's cache
---

Key material generated once and held in Terraform state. Today just
[`keys/signing`](signing) — an ECDSA key pair for the Image Factory's cache
signing.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [signing](signing/) — Generates an ECDSA signing key held in Terraform state.
<!-- END_TERRAFORM_MODULES -->
