---
title: provisioning
description: Terraform state Omni's provisioning capability needs outside the cluster.
stack_backing: Omni's identity and backups
---

State that lives outside the cluster but backs the `provisioning` facet. Today just
[`provisioning/omni`](omni) — a stable UUID for Omni's `config.account.id`, plus the
etcd backup destination.

<!-- BEGIN_TERRAFORM_MODULES -->

## Modules

- [omni](omni/) — Generates Omni's config.account.id and holds an inactive etcd backup S3 config.
<!-- END_TERRAFORM_MODULES -->
