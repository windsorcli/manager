---
title: Registry
description: Self-hosted fleet container registry (Harbor), reachable through the gateway.
---

# Registry

The fleet's own container registry: [Harbor](https://goharbor.io), not another bare
[`distribution`](https://github.com/distribution/distribution) cache. Image Factory's own
`registry` component already fills that narrower role (schematics and cached boot assets,
anonymous, no UI); Harbor is the general-purpose registry an operator or CI pipeline can
push to and browse. It comes up reachable through the gateway with local admin auth.

Installs the official `goharbor/harbor-helm` chart. Hard external dependencies:

- **A dedicated Postgres.** A `harbor-db` CloudNativePG `Cluster` this facet creates
  directly — the same shape Core's own Keycloak facet uses, not the chart's bundled
  database. `sslmode` stays `disable`: unlike Keycloak's operator CR, this chart has no
  CA-bundle field to trust CNPG's own cluster CA with.
- **A local admin password** outside dev mode — Harbor's local auth. SSO via Core's
  identity is wired through an admin-API Job when identity is enabled.
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
necessarily regenerate (`force_destroy: false`).

## Routing

Reachable at `harbor.<domain>` through the shared gateway, with explicit long timeouts on the
HTTPRoute (`request`/`backendRequest: 5m`) for OCI blob pushes — the same shape Image
Factory's own route already sets.

## Configuration

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Substitutions

| Name | Required when | Effect |
|---|---|---|
| `harbor_hostname` | `registry.driver` is `harbor` | Base hostname Harbor's UI/API advertises, from `registry.harbor.hostname` or derived as `harbor.<domain>`. Includes the docker-desktop `:8443` port suffix where the chart's own `externalURL` needs it. |
| `harbor_storage_class` | `registry.driver` is `harbor` | Storage class for the registry PVC when no object store backs it. Defaults to `cluster.storage.class`, or `single`. |
| `harbor_registry_size` | `registry.driver` is `harbor` | Size of the registry PVC when no object store backs it. Defaults to `20Gi`. |
| `harbor_registry_bucket` | `harbor/s3` | Bucket backing Harbor's registry. Built from `object_store.prefix`, the same expression the object-store Terraform module provisions. |
| `harbor_registry_region` | `harbor/s3` | Region embedded in the S3 v4 signature, from `object_store.region`. |
| `harbor_registry_endpoint` | `harbor/s3` | S3 endpoint Harbor's registry writes to, from `object_store.endpoint`. |
| `registry_storage_class` | `registry.driver` is `distribution` | Storage class for the distribution driver's PVC when no object store backs it. Defaults to `cluster.storage.class`, or `single`. |
| `registry_storage_size` | `registry.driver` is `distribution` | Size of the distribution driver's PVC when no object store backs it. Defaults to `registry.distribution.storage_size`, or `10Gi`. |
| `registry_replicas` | `registry.driver` is `distribution` | Replica count for the distribution driver's StatefulSet. 2 under `topology: ha` when object storage backs it (a PVC cannot take two), else 1. |
| `registry_bucket` | `distribution/s3` | Bucket backing the distribution driver. Built from `object_store.prefix`, the same expression the object-store Terraform module provisions. |
| `registry_region` | `distribution/s3` | Region embedded in the S3 v4 signature, from `object_store.region`. |
| `registry_endpoint` | `distribution/s3` | S3 endpoint the distribution driver writes to, from `object_store.endpoint`. |
| `external_domain` | `harbor/gateway` | Domain the gateway route publishes under; the hostname is `harbor.<external_domain>`. Public domain when set, otherwise the private domain or the cluster domain. |
| `keycloak_realm` | `harbor/oidc` | Identity realm the OIDC client registers against, from `identity_effective.realm`. |
| `oidc_issuer` | `harbor/oidc` | External OIDC discovery issuer, from `identity_effective.issuer`. |
| `oidc_admin_group` | `harbor/oidc` | Keycloak group mapped to Harbor's admin role via the OIDC groups claim. Fixed at `platform-admins`. |
| `oidc_verify_cert` | `harbor/oidc` | Whether Harbor verifies the identity provider's TLS certificate. False only in dev mode. |
| `gc_schedule` | `harbor/gc` | Cron expression for Harbor's GC schedule, from `registry.harbor.gc.schedule`. 6 fields, seconds first. |
| `gc_delete_untagged` | `harbor/gc` | Whether GC also deletes untagged artifacts, from `registry.harbor.gc.delete_untagged`. |

## Components

| Component | Enable when | Effect |
|---|---|---|
| `database` | `registry.driver` is `harbor` (default `distribution`) | Dedicated CloudNativePG `Cluster` (`harbor-db`) — Harbor's Postgres, not the chart's bundled one. |
| `harbor` | `registry.driver` is `harbor` (default `distribution`) | Helm release of the official `goharbor/harbor-helm` chart in `harbor`. Local admin auth. |
| `harbor/s3` | `registry.driver` is `harbor` and `object_store.driver` is `hetzner` or `aws` | Backs Harbor with a bucket from the platform's object store instead of a PVC. Own bucket, own destroy policy — not shared with the distribution driver's. |
| `harbor/oidc` | `registry.driver` is `harbor`, `identity.enabled == true`, and `registry.harbor.sso` is not explicitly false | Admin-API Job that registers Harbor's OIDC client in the platform realm and configures Harbor for OIDC auth, group-mapped to `platform-admins`. A named `oidc` resources variant of the `registry` flux system (`registry-resources-oidc`) so it depends on identity without gating Harbor's install or gateway route. |
| `harbor/gateway` | `registry.driver` is `harbor` and `gateway.enabled == true` | HTTPRoute on Core's canonical `external` Gateway. Lives in the resources tier and depends on `gateway-resources`. Without a gateway, reach Harbor by port-forwarding the `harbor` Service in `registry`. |
| `harbor/proxy-cache` | `registry.driver` is `harbor` and `registry.harbor.proxy_cache` has at least one entry | Admin-API Job that creates a Harbor Registry endpoint and proxy-cache Project for each configured upstream. Shares the `admin-jobs` resources variant with `harbor/gc` — both depend only on Harbor's own install, unlike `harbor/oidc`, which also needs identity. |
| `harbor/gc` | `registry.driver` is `harbor` and `registry.harbor.gc.enabled` is not explicitly false (default on) | Admin-API Job that sets Harbor's own GC schedule via its admin API. Harbor's jobservice runs GC on that schedule afterward; the Job only sets the schedule once. Shares the `admin-jobs` resources variant with `harbor/proxy-cache`. |
| `distribution` | `registry.driver` is `distribution` (the default) | Bare, anonymous `distribution/distribution` StatefulSet + Service in `registry`. No auth, no scanning, no UI — a `NetworkPolicy` restricts ingress to image-factory's own pods, in their own namespace. The cheap default for a single internal consumer. |
| `distribution/pvc` | `registry.driver` is `distribution` and no object store backs it | Backs the distribution driver with a PersistentVolumeClaim on the cluster's default storage class. |
| `distribution/s3` | `registry.driver` is `distribution` and `object_store.driver` is `hetzner` or `aws` | Backs the distribution driver with a bucket from the platform's object store instead of a PVC. |

## Dependencies

| Add-on | Required when | Reason |
|---|---|---|
| `pki` | `registry.driver` is `harbor` | Harbor is served over TLS, and the certificate is issued by the cluster issuer cert-manager installs. |
| `gateway` | `registry.driver` is `harbor` and `gateway.enabled == true` | The route CRDs have to exist before the chart renders an HTTPRoute. |
| `database` | `registry.driver` is `harbor` | The CloudNativePG operator has to exist before this facet's own `harbor-db` Cluster can reconcile. |
| `identity` | `harbor/oidc` | The OIDC client registers against the platform realm's admin API. |

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
