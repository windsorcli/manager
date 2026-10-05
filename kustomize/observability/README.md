---
title: Observability
description: Manager-authored Grafana dashboards and Prometheus alert rules for Omni and Image Factory, layered on Core's telemetry install.
stack_backing: Dashboards & alerts
---

Dashboards and alert rules for the services Manager adds — Omni and the Image
Factory — layered on top of the Grafana and Prometheus Core's own `telemetry`
capability already installs. This add-on ships no infrastructure of its own,
only content for infrastructure Core provides.

The Flux Kustomization is named `manager-observability`, not `observability`
or `telemetry` — those names belong to Core's own Kustomizations. A facet
contributing to either of Core's names would merge directly into Core's
Kustomization and resolve its components against Core's kustomize tree, not
Manager's, and silently fail.

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Components

### `grafana-dashboards`

Grafana dashboards for the services Manager adds, loaded by Core's grafana sidecar into the `Provisioning` folder. Built from each service's own native metrics — no upstream dashboard exists for either.

| Variant | Enabled when | Effect |
|---|---|---|
| `image-factory` | `provisioning.image_factory.enabled: true` AND `telemetry.metrics.enabled: true` | ConfigMap `grafana-dashboard-image-factory` in `system-observability`, panelling `image_factory_assets_built_total`, `image_factory_assets_build_latency_seconds`, `image_factory_schematic_cache_*`, and `http_request_duration_seconds` — the same metrics `prometheus-alerts/image-factory` alerts on. |
| `omni` | `provisioning.enabled: true` AND `telemetry.metrics.enabled: true` | ConfigMap `grafana-dashboard-omni` in `system-observability`, panelling `omni_machines`, `omni_connected_machines`, `omni_clusters`, `omni_machines_version`, `omni_siderolink_last_handshake_seconds`, and `http_requests_total`. Works from what `telemetry.metrics.enabled` alone scrapes — does not depend on the optional `omni/exporter` component. |

### `prometheus-alerts`

Supplemental PrometheusRule alerts for the services Manager adds, each with a `promtool`-testable `prometheus-rule.test.yaml`.

| Variant | Enabled when | Effect |
|---|---|---|
| `image-factory` | `provisioning.image_factory.enabled: true` AND `telemetry.metrics.enabled: true` | PrometheusRule `image-factory-alerts` in `provisioning`. Covers factory absence and an elevated 5xx rate against the `image-factory-metrics` job Core's `image-factory/prometheus` component exposes. |
| `omni` | `provisioning.enabled: true` AND `telemetry.metrics.enabled: true` | PrometheusRule `omni-alerts` in `provisioning`. Covers Omni's own supplemental alert conditions against the `omni-metrics` job Core's `omni/prometheus` component exposes. |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `telemetry-install` | always | Both dashboards and alerts scrape or query metrics Prometheus and Grafana provide; Core's telemetry install must be reconciling first. |

<!-- END_KUSTOMIZE_DOCS -->
