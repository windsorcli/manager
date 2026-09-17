---
title: Registry
description: Self-hosted fleet container registry (Harbor), reachable through the gateway with SSO and proxy-cache projects.
stack_backing: Container registry
---

The fleet's own container registry: [Harbor](https://goharbor.io). An operator or CI
pipeline can push to it, browse it, scan it, and mirror from it. Image Factory's own
`registry` component is separate and narrower: anonymous, no UI, just schematics and
cached boot assets.

Installs the official `goharbor/harbor-helm` chart. Hard dependencies:

- **A dedicated Postgres.** A `harbor-db` CloudNativePG `Cluster`, not the chart's bundled
  database. `sslmode` stays `disable`: this chart has no CA-bundle field for CNPG's cluster
  CA.
- **Auth.** A local admin password outside dev mode, or SSO against Keycloak (`harbor/oidc`,
  an admin-API Job). SSO needs hosted Keycloak (`identity.driver: keycloak`) and a gateway —
  the Job registers a redirect URI on Harbor's gateway route. Set `registry.harbor.sso` to
  `false` to keep local-admin auth with identity enabled.
- **A gateway.** Harbor's UI/API reach Core's canonical `external` Gateway. TLS terminates
  there; Harbor serves plain HTTP.

## Storage

Object-store-backed (Hetzner/AWS S3) when the platform provides one, a PVC otherwise. Harbor
gets its own bucket, not Image Factory's: both use the same storage layout, so a shared
bucket risks path collisions, and the two want different destroy settings
(`force_destroy: true` for Image Factory's rebuildable cache, `false` for Harbor's).

## Routing

Reachable at `harbor.<domain>` through the shared gateway. The HTTPRoute sets long timeouts
(`request`/`backendRequest: 5m`) for OCI blob pushes. Whether Envoy/Cilium need an
additional large-body policy is unresolved.

## Configuration

<!-- BEGIN_KUSTOMIZE_DOCS -->

## Substitutions

| Name | Required when | Effect |
|---|---|---|
| `harbor_hostname` | `registry.driver` is `harbor` | Base hostname Harbor's UI/API advertises, from `registry.harbor.hostname` or derived as `harbor.<domain>`. Includes the docker-desktop `:8443` port suffix where the chart's own `externalURL` needs it. |
| `harbor_storage_class` | `registry.driver` is `harbor` | Storage class for the registry PVC when no object store backs it. Defaults to `cluster.storage.class`, or `single`. |
| `harbor_registry_size` | `registry.driver` is `harbor` | Size of the registry PVC when no object store backs it. Defaults to `20Gi`. |
| `harbor_db_storage_size` | `registry.driver` is `harbor` | Size of the PVC backing Harbor's dedicated CNPG database, from `registry.harbor.db_storage_size`. Defaults to `5Gi`. |
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

### `harbor/database`

_Enabled when `registry.driver` is `harbor` (default `distribution`)._

Dedicated CloudNativePG `Cluster` (`harbor-db`) — Harbor's Postgres, not the chart's bundled one.

### `harbor/database/ha`

_Enabled when `registry.driver` is `harbor` and `topology: ha`._

Scales the CloudNativePG `Cluster` to 3 instances with required pod anti-affinity, so each Postgres instance lands on a distinct node.

### `harbor/db-tls`

_Enabled when `registry.driver` is `harbor` (default `distribution`)._

Copies `ca.crt` out of CNPG's `harbor-db-ca` keypair Secret into a cert-only `harbor-db-ca-cert` Secret, so Harbor's `caBundleSecretName` (which mounts the whole named Secret with no key restriction) never gets the private key too. Backs `sslmode: verify-full` on Harbor's database connection.

### `harbor`

_Enabled when `registry.driver` is `harbor` (default `distribution`)._

Helm release of the official `goharbor/harbor-helm` chart in `harbor`. Local admin auth.

### `harbor/s3`

_Enabled when `registry.driver` is `harbor` and `object_store.driver` is `hetzner` or `aws`._

Backs Harbor with a bucket from the platform's object store instead of a PVC. Own bucket, own destroy policy — not shared with the distribution driver's.

### `harbor/oidc`

_Enabled when `registry.driver` is `harbor`, `identity.enabled == true`, `identity.driver` is `keycloak`, `gateway.enabled == true`, and `registry.harbor.sso` is not explicitly false._

Admin-API Job that registers Harbor's OIDC client in the platform realm and configures Harbor for OIDC auth, group-mapped to `platform-admins`. Needs hosted Keycloak and a gateway, since the Job registers a redirect URI on Harbor's gateway route. A named `oidc` resources variant of the `registry` flux system (`registry-resources-oidc`) so it depends on identity without gating Harbor's install or gateway route.

### `harbor/gateway`

_Enabled when `registry.driver` is `harbor` and `gateway.enabled == true`._

HTTPRoute on Core's canonical `external` Gateway. Lives in the resources tier and depends on `gateway-resources`. Without a gateway, reach Harbor by port-forwarding the `harbor` Service in `registry`.

### `harbor/proxy-cache`

_Enabled when `registry.driver` is `harbor` and `registry.harbor.proxy_cache` has at least one entry._

Admin-API Job that creates a Harbor Registry endpoint and proxy-cache Project for each configured upstream. Shares the `admin-jobs` resources variant with `harbor/gc` — both depend only on Harbor's own install, unlike `harbor/oidc`, which also needs identity.

### `harbor/gc`

_Enabled when `registry.driver` is `harbor` and `registry.harbor.gc.enabled` is not explicitly false (default on)._

Admin-API Job that sets Harbor's own GC schedule via its admin API. Harbor's jobservice runs GC on that schedule afterward; the Job only sets the schedule once. Shares the `admin-jobs` resources variant with `harbor/proxy-cache`.

### `harbor/image-factory`

_Enabled when `registry.driver` is `harbor` and `provisioning.image_factory.enabled == true`._

Admin-API Job that creates an `image-factory` Harbor project and a scoped push/pull robot account, then writes a dockerconfigjson Secret in `provisioning` for the factory's own pod to mount. Needs RBAC to write that Secret cross-namespace — the only admin-API Job here that talks to the Kubernetes API, not just Harbor's.

### `harbor/prometheus`

_Enabled when `registry.driver` is `harbor` and `telemetry.metrics.enabled == true`._

Turns on the chart's own `metrics` block plus a ServiceMonitor (30s interval). The chart adds a `/metrics` port to each component's existing Service rather than a dedicated metrics Service; everything scrapes under one `job=harbor`.

### `distribution`

_Enabled when `registry.driver` is `distribution` (the default)._

Bare, anonymous `distribution/distribution` StatefulSet + Service in `registry`. No auth, no scanning, no UI — a `NetworkPolicy` restricts ingress to image-factory's own pods, in their own namespace. The cheap default for a single internal consumer.

### `distribution/pvc`

_Enabled when `registry.driver` is `distribution` and no object store backs it._

Backs the distribution driver with a PersistentVolumeClaim on the cluster's default storage class.

### `distribution/s3`

_Enabled when `registry.driver` is `distribution` and `object_store.driver` is `hetzner` or `aws`._

Backs the distribution driver with a bucket from the platform's object store instead of a PVC.

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

Bucket-backed, when the platform has its own object storage:

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
