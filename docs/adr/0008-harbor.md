---
title: "ADR-0008: Harbor — a fleet registry, not another bare distribution cache"
description: "Image Factory's own facet already names the gap it's working around: its in-cluster registry is a bare `distribution` cache with no scanning, no RBAC, no UI, and no replication, and its docs say plainly that once Manager's Harbor lands, the factory points at it instead. This ADR picks Harbor (the official `goharbor/harbor-helm` chart) as that fleet-wide registry, deployed the same way every other stateful addon in this repo is: a dedicated CloudNativePG Postgres Cluster (Keycloak's own precedent, not the chart's bundled database), object_store-backed S3 storage in its own bucket (not shared with Image Factory's), the chart's bundled Redis (no shared-Redis precedent exists to build on, and Redis holds nothing that needs to survive a restart), and exposure through the shared gateway. SSO against Core's Keycloak realm ships alongside the initial deployment, wired through an admin-API Job the same shape Omni's own SAML client registration uses (Harbor has no CRD/values-level OIDC). Deferred: proxy-cache projects for the reduced-egress/air-gapped motivation, migrating Image Factory's own registry onto Harbor, and scheduled garbage collection — each waits on Harbor being proven reachable and authenticated first, the same phasing discipline ADR-0004 used for Omni."
---

# ADR-0008: Harbor — a fleet registry, not another bare distribution cache

## Status

Proposed (2026-08-09). Depends on [ADR-0001](0001-layering-on-core.md). Needs `gateway` and
Core's `database` (CloudNativePG operator) turned on, and Manager's own `object_store`
resolution (`config-object-store.yaml`) — no new ADR-level dependency there, it's the same
config `addon-image-factory.yaml` already reads. The OIDC step depends on
[ADR-0002](0002-identity.md) (the platform Keycloak realm) the same way
[ADR-0004](0004-omni.md) decision 2 does. Referenced by [ADR-0007](../roadmap-v0.1.0.md)
(Manager's own state) once it exists — Harbor's Postgres and bucket join Omni's etcd and the
identity database as things that need a backup story, not something this ADR decides.

## Context

This came out of a horizontal-vs-vertical framing decision, not a roadmap ADR slot — the
original roadmap table never named Harbor; it named "Image factory" as 0005 and that number
got claimed by an unrelated SideroLink gateway-exposure decision instead, so Image Factory
shipped without a formal ADR of its own. Harbor was picked over deepening Omni's own
production-hardening (HA, external etcd) after weighing that ADR-0004 decision 3 already
proved the core provisioning loop works (a real machine joined a real cluster via the local
SideroLink spike) — hardening a proven loop has a lower ceiling right now than adding a
functional pillar this fleet doesn't have at all yet. The roadmap's own "Deferred" section
lists Harbor for exactly this reason: *"Needed for the disconnected install, not for a first
cut that pulls from upstream registries."* There's now a first cut; the disconnected-install
motivation is still live, and there's a second, independent motivation that showed up
mid-build: Image Factory's own facet doc names Harbor by name as the thing its bare in-cluster
registry is a placeholder for.

Image Factory's `registry` component today is the `distribution` project directly — an
anonymous, unauthenticated OCI store with no scanning, no per-repo RBAC, no web UI, and no
replication/mirroring story, reachable only in-cluster. That's fine for what it does (hold
generated schematics and cached boot assets nothing else touches), but it's not something a
second consumer should share, and it's not something an operator can browse, scan, or point a
CI pipeline's `docker push` at. Harbor is the natural answer to both: a real fleet registry
general enough for CI/operator pushes, and (via proxy-cache projects, still deferred) a
pull-through mirror downstream clusters can use instead of reaching `ghcr.io`/`docker.io`
directly.

## Decision

**1. Deploy Harbor via the official `goharbor/harbor-helm` chart, with SSO shipped
alongside it and three items still deferred.** Delivered: Harbor up, reachable through the
gateway, SSO against Keycloak wired the same way Omni's own SAML client registration is
(decision 6). Deferred: proxy-cache projects for reduced egress, Image Factory's registry
migrated onto Harbor, and scheduled garbage collection — each waits on Harbor being proven
reachable and authenticated first. This is the same phasing discipline ADR-0004 used for
Omni —
land the reachable thing, defer what depends on it being proven — not a new pattern.

The schema is `registry.enabled` / `registry.driver` (default `harbor`) /
`registry.harbor.*`, not a flat `harbor.*` key — capability-plus-driver, the same shape
`identity.driver`/`identity.keycloak.*` and `database.postgres.driver` already use in
Core, so a second registry driver (if one is ever needed) is additive, not a breaking
schema change. The kustomize directory is `kustomize/registry/`, not `kustomize/harbor/`,
for the same reason `observability`/`provisioning` are category names rather than product
names — the still-deferred Image Factory migration is exactly the kind of second tenant that
directory is already shaped to hold. The Kubernetes namespace is `registry` for the same
reason: every namespace in the fleet is a category name (`provisioning`, `system-identity`,
`system-gateway`), never the product that happens to fill it — `system-identity` is
essentially just Keycloak yet still takes the category name. `registry` carries no
`system-` prefix, matching `provisioning`, since Core reserves that prefix for its own
infra. Harbor's own resources keep their `harbor`/`harbor-*` names inside it, and the deferred
Image Factory migration lands as a second tenant of the same namespace. The flux
Kustomization name is `registry` (matching the directory implicitly, no `path:` override
needed), the same relationship Core's own `identity` flux system has to the keycloak-specific
pieces inside it.

**2. Postgres is a dedicated CloudNativePG `Cluster`, the same shape Keycloak's already
uses, not the chart's bundled database.** `database.type: external` in Harbor's own values,
pointed at a `harbor-db` `Cluster` this facet creates directly (mirroring
`kustomize/identity/resources/keycloak/database.yaml`): `bootstrap.initdb` creates one
database and owner role, CNPG auto-publishes the `harbor-db-app` credentials Secret and the
`harbor-db-rw` Service. Keycloak's CR-level `truststores`/`sslfactory` CA-trust wiring has no
Harbor-chart equivalent — Harbor's external-DB support is coarser (a `sslmode` string, no
CA-bundle field) — so this ships without `sslmode=verify-full`'s CA validation until that
gap is confirmed closeable; revisit once the exact `existingSecret` key contract Harbor's
chart expects is confirmed against the pinned chart version, not paraphrased docs.

**3. Redis is the chart's bundled instance, not a new shared service.** Nothing in Core or
Manager runs a shared Redis today, and Harbor's Redis holds cache/session/job-queue data, not
anything that needs to survive a pod restart the way Postgres or the registry's blobs do —
standing up new shared infrastructure for that would be premature, the same reasoning ADR-0004
decision 3 used to defer external etcd until there's a second control-plane node that actually
needs it.

**4. Storage is `object_store`-backed S3 when the platform provides one, PVC otherwise — in
Harbor's own bucket, not Image Factory's.** Same driver/region/endpoint/credential resolution
`config-object-store.yaml` already computes (`object_store.driver`, shared across both
consumers), but a second bucket (`${object_store.prefix}-harbor`), provisioned by a second
named `terraform:` stack entry against the same `object-store/hetzner`/`object-store/aws`
module Image Factory's own bucket uses — not a shared bucket, and not a module change. Two
reasons: Harbor's registry component is the same `distribution` storage layout Image Factory's
already is, and while blob paths are content-addressed (safe to collide), manifest and
repository-namespace paths are not — a shared bucket root risks a real collision, not just an
untidy one. Second, the two buckets don't want the same destroy/versioning semantics: Image
Factory's holds a rebuildable cache (`force_destroy: true` is deliberate, per that module's own
comment), Harbor's holds images an operator or CI pipeline pushed and can't necessarily
regenerate — `force_destroy: false` (and versioning where the platform module supports it,
i.e. AWS, not Hetzner) is the right default for that data, and the module's `force_destroy`/
`versioning` inputs apply per-invocation already, so a second named stack entry gets its own
settings for free — no widening the module's `list(string)` + shared-bool shape into a
per-bucket map.

**5. Exposed through the shared gateway, `expose.type: clusterIP` with TLS terminated at the
Gateway** — the same posture every other addon here uses (Keycloak, Grafana, Image Factory,
Omni), not Harbor's own ingress-oriented defaults. Needs explicit long timeouts on the
HTTPRoute for blob pushes, the same `timeouts: {request: 5m, backendRequest: 5m}` shape
Image Factory's own route already sets. **Open implementation risk, not resolved by this
ADR**: nginx's `proxy-body-size: 0` (unlimited chunked-upload body) has no confirmed Gateway
API/Envoy/Cilium equivalent yet — needs a spike against both gateway drivers before this is
considered done, not a design decision to guess at here. The gateway route is its own
resources variant, not a `requires:` on installing Harbor at all — the same shape
`addon-observability.yaml` uses for Grafana's own route, so Harbor still installs without a
gateway (reachable by port-forwarding the `harbor` Service) rather than failing composition.

**6. SSO is an admin-API Job, not a Helm value — Harbor's chart has no OIDC configuration
surface at all.** Unlike Keycloak's `KeycloakRealmImport` CRD, turning Harbor's auth mode to
OIDC is a post-boot REST call against the bootstrap admin session, so `harbor/oidc` registers
the OIDC client in the platform realm and then configures Harbor over its own API, not a
values field. It's a named `oidc` resources variant of the `registry` flux system
(`registry-resources-oidc`, `dependsOn: [registry-install, identity-resources]`) — the same
shape `addon-identity.yaml` uses to sequence its own `database` resources variant ahead of the
Keycloak CR — rather than a component of Harbor's install tier, so Harbor's install and gateway
route come up regardless of whether identity is enabled. That's a deliberate difference from
Omni's own `omni/saml-client` Job, which *is* a component of `omni-install` and accepts an
unconditional `dependsOn: [identity-resources]` on the whole system: Omni has no toggle to run
without identity, Harbor does — `registry.harbor.sso` (default `true`) turns it off explicitly
if an operator wants Harbor on local-admin auth even with identity enabled. Harbor's own local
admin credential still exists either way, materialized the same way every other bootstrap-admin
secret in this repo is — SSO adds a second login path, it doesn't replace the first.

## Consequences

- Two independently-authenticated OCI registries run in the fleet until
  the still-deferred Image Factory migration lands: Image Factory's own `registry` component (schematics,
  cached boot assets) and Harbor (everything else). That's a deliberate, named consequence of
  the phasing, not an oversight — collapsing them on day one would mean shipping Harbor's
  OIDC/migration work before Harbor itself is proven reachable.
- Harbor's chart no longer ships Notary/content-trust (dropped upstream in favor of
  Cosign-based signing outside the chart) — image signing, if this fleet ever wants it, is a
  separate decision this ADR doesn't make.
- Confirmed empirically while building this: a schema `default:` is not visible to another
  facet's `when:` condition — only facet-computed `config:` values are (per ADR-0001's
  documented cross-facet visibility rule). Every `when:` that reads a driver-shaped field
  elsewhere in this codebase re-states its default via `??` (`(identity.driver ?? 'keycloak')
  == 'keycloak'`), and a facet that fans another facet's flag on has to re-state that facet's
  own defaults too, not just the flag itself — `addon-registry.yaml` re-states
  `database.postgres.driver ?? 'cloudnativepg'` for exactly this reason, the same way
  `addon-identity.yaml` already does for its own database dependency. Worth a project-wide
  note somewhere more visible than this ADR if it isn't already documented.
- Trivy (vulnerability scanning) ships on by default with the chart — real CPU/memory
  footprint on top of core/portal/jobservice/registry/redis, sized the same
  workload-characteristics-first way `provisioning.image_factory`'s own resources were: bursty
  (scans run on push/schedule, not continuously), not the steady-state assumption a fixed
  multiplier would imply.
- The CNPG CA-trust gap in decision 2 means Harbor's database connection may ship without
  full TLS certificate verification — flagged explicitly so it isn't silently
  carried forward as if it were resolved.
- The still-deferred proxy-cache motivation (mirroring `ghcr.io`/`docker.io` for downstream clusters)
  depends on Harbor's own per-registry-provider support; native `ghcr.io` proxy-cache support
  is community-reported working, not officially documented — that work needs to confirm this
  against the pinned Harbor version before downstream clusters are pointed at it, not assume
  it from this ADR.
- ADR-0007 (Manager's own state, not yet written) now has a second Postgres Cluster and a
  second bucket to account for, alongside Omni's etcd and the identity database.

## Alternatives considered

**Keep Image Factory's bare `distribution` registry as the fleet's only registry, skip Harbor
entirely.** Rejected: it has no scanning, no RBAC, no UI, and no replication/mirroring story,
none of which a single-purpose asset cache needs but a general fleet registry does. Image
Factory's own facet docs already named Harbor as the intended successor before this ADR
existed.

**A single shared bucket for both Image Factory and Harbor.** Rejected per decision 4 —
real path-collision risk in a storage layout both consumers share verbatim, and the two
buckets want different destroy/versioning semantics (rebuildable cache vs. operator-pushed
data) that a shared bucket can't express without also sharing settings neither consumer
actually wants.

**OIDC from day one, no local-admin phase.** Rejected as the wrong order of operations for
the same reason ADR-0004 phased Omni's HA/backup out: Harbor's OIDC path is a Job-based
integration with no chart-level shortcut, and building it before Harbor itself is confirmed
reachable through the gateway (including the unresolved body-size/timeout question in
decision 5) means debugging two unproven things at once instead of one at a time.

**An external, shared Redis addon.** Rejected as premature — no consumer in this repo runs
Redis today, Harbor's own Redis holds nothing precious, and standing up shared infrastructure
for a future second consumer that doesn't exist yet repeats the same over-provisioning ADR-0004
decision 3 already rejected for etcd.
