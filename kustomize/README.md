---
title: Kustomize add-on reference
description: Reference index for the Kustomize add-ons in this blueprint.
---

# kustomize/

Reference index for the Kustomize add-ons in this blueprint. See
[GUIDELINES.md](GUIDELINES.md) for authoring conventions.

## Add-ons

<!-- BEGIN_INDEX -->

| Path | Purpose |
|---|---|
| [observability](observability/) | Manager-authored Grafana dashboards and Prometheus alert rules for Omni and Image Factory, layered on Core's telemetry install. |
| [provisioning](provisioning/) | Downstream cluster provisioning — self-hosted Talos image factory and Sidero Omni, turned on together by provisioning.enabled. |
| [registry](registry/) | Self-hosted fleet container registry (Harbor), reachable through the gateway with SSO and proxy-cache projects. |
<!-- END_INDEX -->
