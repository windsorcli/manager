---
title: Manager
description: Management cluster blueprint layered on top of core.
---

# Manager

Manager is a Windsor blueprint for a management cluster. It layers on top of
[Core](https://github.com/windsorcli/core), which provides the Kubernetes
platform, and adds the control-plane services that operate a fleet of
downstream clusters. Includes self-hosted Omni, the Talos image factory,
Harbor, and Cluster API.

<!-- BEGIN_STACK_INDEX -->

## Infrastructure

### Keys — Image Factory's cache
- [signing](../terraform/keys/signing)

### Object store — S3 buckets for Image Factory & Harbor
- [aws](../terraform/object-store/aws)
- [hetzner](../terraform/object-store/hetzner)

### Provisioning — Omni's identity and backups
- [omni](../terraform/provisioning/omni)

## Cluster

### Observability — Dashboards & alerts
- [observability](../kustomize/observability)

### Provisioning — Fleet provisioning
- [provisioning](../kustomize/provisioning)

### Registry — Container registry
- [registry](../kustomize/registry)

<!-- END_STACK_INDEX -->

## Configuration

Manager is configured through `values.yaml` for the current context, the
same as Core. See the [README](https://github.com/windsorcli/manager) for
the full service set.
