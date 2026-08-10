---
title: Registry
description: Self-hosted fleet container registry (Harbor) — Phase 1 of ADR-0008, reachable and locally authenticated.
---

# Registry

The fleet's own container registry: [Harbor](https://goharbor.io), not another bare
[`distribution`](https://github.com/distribution/distribution) cache. Image Factory's own
`registry` component already fills that narrower role (schematics and cached boot assets,
anonymous, no UI); Harbor is the general-purpose registry an operator or CI pipeline can
actually push to, browse, and (Phase 2) scan and mirror from. See
[ADR-0008](/docs/adr/0008-harbor.md) for the full decision record and the two-phase plan —
this add-on implements Phase 1 only: Harbor up, reachable through the gateway, locally
authenticated. Nothing else in the fleet points at it yet.

Installs the official `goharbor/harbor-helm` chart. Hard external dependencies:

- **A dedicated Postgres.** A `harbor-db` CloudNativePG `Cluster` this facet creates
  directly — the same shape Core's own Keycloak facet uses, not the chart's bundled
  database. `sslmode` stays `disable`: unlike Keycloak's operator CR, this chart has no
  CA-bundle field to trust CNPG's own cluster CA with (a known Phase 1 gap, not silently
  papered over).
- **A local admin password** outside dev mode — the chart's only auth method until Phase 2
  wires OIDC via an admin-API Job (Harbor has no CRD/values-level OIDC, unlike Keycloak's
  realm import).
- **A gateway.** Harbor's UI/API are reached through Core's canonical `external` Gateway,
  TLS terminating there — Harbor itself serves plain HTTP.

## Storage

Object-store-backed (Hetzner/AWS S3) when the platform provides one, a PVC otherwise — the
same `object_store` resolution `config-object-store.yaml` computes for Image Factory's own
registry, but Harbor's own bucket, not a shared one. Two reasons, not just tidiness: Harbor's
registry component is the same `distribution` storage layout Image Factory's already is, so a
shared bucket risks a real path collision, not just an untidy one; and the two buckets want
different destroy semantics — Image Factory's holds a rebuildable cache
(`force_destroy: true`), Harbor's holds images an operator or CI pipeline pushed and can't
necessarily regenerate (`force_destroy: false`). See
[ADR-0008](/docs/adr/0008-harbor.md) decision 4.

## Routing

Reachable at `harbor.<domain>` through the shared gateway, with explicit long timeouts on the
HTTPRoute (`request`/`backendRequest: 5m`) for OCI blob pushes — the same shape Image
Factory's own route already sets. Whether Envoy/Cilium need an additional large-body policy
beyond that timeout is an open spike ADR-0008 flags, not resolved here.

## Configuration

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Substitutions

| Name | Required when | Effect |
|---|---|---|
| `harbor_hostname` | always | Base hostname Harbor's UI/API advertises, from `registry.harbor.hostname` or derived as `harbor.<domain>`. Includes the docker-desktop `:8443` port suffix where the chart's own `externalURL` needs it. |
| `harbor_storage_class` | always | Storage class for the registry PVC when no object store backs it. Defaults to `cluster.storage.class`, or `single`. |
| `harbor_registry_size` | always | Size of the registry PVC when no object store backs it. Defaults to `20Gi`. |
| `harbor_registry_bucket` | `harbor/s3` | Bucket backing the registry. Built from `object_store.prefix`, the same expression the object-store Terraform module provisions. |
| `harbor_registry_region` | `harbor/s3` | Region embedded in the S3 v4 signature, from `object_store.region`. |
| `harbor_registry_endpoint` | `harbor/s3` | S3 endpoint the registry writes to, from `object_store.endpoint`. |
| `external_domain` | always | Domain the gateway route publishes under; the hostname is `harbor.<external_domain>`. Public domain when set, otherwise the private domain or the cluster domain. |

## Components

| Component | Enable when | Effect |
|---|---|---|
| `database` | always | Dedicated CloudNativePG `Cluster` (`harbor-db`) — Harbor's Postgres, not the chart's bundled one. See ADR-0008 decision 2. |
| `harbor` | always | Helm release of the official `goharbor/harbor-helm` chart in `harbor`. Local admin auth only in Phase 1 — see ADR-0008. |
| `harbor/s3` | `object_store.driver` is `hetzner` or `aws` | Backs the registry with a bucket from the platform's object store instead of a PVC. Own bucket, own destroy policy — not shared with image-factory's. See ADR-0008 decision 4. |
| `harbor/gateway` | always | HTTPRoute on Core's canonical `external` Gateway. Lives in the resources tier and depends on `gateway-resources`. |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `pki` | always | Harbor is served over TLS, and the certificate is issued by the cluster issuer cert-manager installs. |
| `gateway` | always | The route CRDs have to exist before the chart renders an HTTPRoute. |
| `database` | always | The CloudNativePG operator has to exist before this facet's own `harbor-db` Cluster can reconcile. |

<!-- END_KUSTOMIZE_DOCS -->

## Recipes

Minimal, PVC-backed (no platform object store):

```yaml
gateway:
  enabled: true
registry:
  enabled: true
  harbor:
    admin_password: ${secret("Developer", "harbor", "admin_password")}
```

Bucket-backed, on a platform with its own object storage — the bucket is provisioned by the
object-store Terraform module, same as Image Factory's own:

```yaml
platform: aws
gateway:
  enabled: true
aws:
  region: us-west-2
registry:
  enabled: true
  harbor:
    admin_password: ${secret("Developer", "harbor", "admin_password")}
```

## Not covered yet (Phase 2)

- **OIDC.** Local admin auth only — see ADR-0008 decision 6 for why this needs a Job, not a
  values field.
- **Proxy-cache projects.** The actual "reduce egress / air-gapped" motivation — mirroring
  `ghcr.io`/`docker.io` so downstream clusters pull from Harbor instead. Native `ghcr.io`
  proxy-cache support is community-reported, not officially documented; needs confirming
  against the pinned chart version before downstream clusters are pointed at it.
- **Image Factory migration.** Image Factory's own `registry` component keeps running
  independently until this lands — two OCI registries coexist in the fleet until then, a
  named consequence of the phasing, not an oversight.
- **Garbage collection scheduling.** Harbor's GC is a REST API call against a running
  instance, not a standalone binary — needs a CronJob-shaped Job, the same pattern the OIDC
  bootstrap Job will use.
