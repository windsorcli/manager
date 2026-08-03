---
title: keys/omni-account-id
description: Generates Omni's config.account.id, held in Terraform state.
---

# keys/omni-account-id

Generates a UUID for Omni's `config.account.id` and keeps it in state, so every apply
returns the same value. Omni's Helm chart refuses to install without one, and Omni's own
docs require it stay fixed for the lifetime of the installation — a changed ID looks like
a different account.

Consumed through `terraform_output("omni-account-id", "id")`.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
