---
title: "ADR-0010: registry gets a second driver — distribution — and image factory becomes just a consumer"
description: "Image Factory ran its own bare, anonymous distribution registry directly, entirely separate from the registry facet ADR-0008 built for Harbor — the exact two-registries state ADR-0008 named as a deliberate, temporary consequence of phasing. This ADR closes that gap the other way from ADR-0008's original plan: rather than migrating Image Factory onto Harbor specifically, registry.driver gets a second value (distribution, the cheap default) so registry becomes the single owner of \"a registry\" regardless of which driver backs it, and Image Factory becomes purely a consumer — reading registry_effective the same way any facet reads another's computed config, never owning its own registry component again. Turning registry.driver: harbor on for a fleet that also runs Image Factory does not yet fully work: Harbor requires authenticated push and nothing here issues Image Factory a credential for it. That's a deliberately separate, smaller follow-up, not blocking this one."
---

# ADR-0010: registry gets a second driver — distribution — and image factory becomes just a consumer

## Status

Proposed (2026-09-12). Depends on [ADR-0008](0008-harbor.md) (the `registry` facet, capability-plus-driver
shape) and [ADR-0001](0001-layering-on-core.md) (Image Factory is wholly Manager's own construct,
free to redesign without a Core dependency). Named by ADR-0008 as the still-deferred "Image Factory
migration"; this ADR is that migration, done as a driver generalization rather than a one-off
point-Image-Factory-at-Harbor change. A second, smaller ADR/PR follows for Harbor push credentials
(decision 4 below) — not blocking this one.

## Context

Image Factory ran its own registry from day one: a bare `ghcr.io/distribution/distribution`
StatefulSet in `kustomize/provisioning/install/registry/`, anonymous, unauthenticated, reachable
only by the factory's own pods in the same namespace via a `NetworkPolicy`. This is exactly the gap
[ADR-0008](0008-harbor.md)'s Context section named when it picked Harbor as the fleet's real
registry — and exactly the "two independently-authenticated OCI registries" ADR-0008's Consequences
accepted as temporary, pending "the still-deferred Image Factory migration."

**A straight migration (point Image Factory's existing config at Harbor) would have worked, but
would have thrown away a cheaper, more general answer.** Image Factory's only registry-facing
schema surface (`provisioning.image_factory.registry.schematic.*`) already exists purely to let an
operator point at *some* registry — it never assumed the registry was Image Factory's own. Once
`registry.driver` (ADR-0008) already existed as a capability-plus-driver toggle with one value
(`harbor`), adding a second value for exactly what Image Factory used to run itself turns "registry"
into the single fleet-wide owner of *a* registry, and Image Factory into a pure consumer — the same
relationship Harbor's own OIDC/proxy-cache/GC admin-API Jobs already have with the `identity`
capability they consume without owning.

**Not every fleet wants Harbor's weight for a single internal consumer.** Harbor needs its own
Postgres Cluster, its own bucket, an admin password, and (per ADR-0008) real CPU/memory for Trivy.
A fleet running only Image Factory, with nothing else wanting a browsable, scanned, RBAC'd registry,
gains nothing from that cost. `distribution` is the new driver's name — the literal upstream project
name, the same convention `harbor` itself already sets (not a generic word like `none` or `bare`,
and deliberately not the ambiguous `registry` itself).

**Harbor requires authenticated push; the bare store never did.** This is the one real gap this ADR
does not close. Image Factory's chart (`ghcr.io/siderolabs/charts/image-factory` 1.7.0) has no
values-level credential field for its own outbound schematic/cache/installer pushes at all — the
established pattern for giving a `go-containerregistry`-based client ambient push credentials is a
mounted `~/.docker/config.json`-shaped Secret plus a `DOCKER_CONFIG` env var, which the chart's
generic `extraVolumes`/`extraVolumeMounts`/`env` fields support but nothing here wires up yet. Doing
that right needs a Harbor robot account (a new admin-API Job, the first one in this repo that also
needs Kubernetes RBAC to write a Secret cross-namespace into `provisioning`) — a genuinely separate,
smaller unit of work from the driver generalization itself.

## Decision

**1. `registry.driver` gets a second value, `distribution`, and it's the default.** `harbor` remains
opt-in for the full-featured registry; `distribution` is the bare, anonymous store Image Factory used
to run itself, now owned by the `registry` facet instead. Defaulting to the cheap option (not
`harbor`) matters specifically because of decision 3 below — enabling Image Factory should not
silently commit a fleet to standing up Harbor's full stack.

**2. The bare registry's kustomize moves from `kustomize/provisioning/install/registry/` to
`kustomize/registry/install/distribution/`, renamed throughout (Service/StatefulSet/NetworkPolicy
`registry` → `distribution`), namespace `provisioning` → `registry`.** Image Factory's own pods stay
in `provisioning`; the `NetworkPolicy` now needs a `namespaceSelector` (the automatic
`kubernetes.io/metadata.name` label every namespace carries) alongside the existing pod selector to
admit cross-namespace traffic — the one genuinely new piece of Kubernetes mechanism this move needed.

**3. `addon-provisioning.yaml` turns `registry.enabled` on whenever Image Factory is enabled and no
external registry is named, and stops computing anything registry-specific itself — no bucket
terraform, no storage substitutions, no `registry`/`registry/pvc`/`registry/s3` components.** It
reads `registry_effective` — `addon-registry.yaml`'s own computed config (`driver`, in-cluster
`hostname`, `insecure`) — the same cross-facet-config pattern `identity_effective`/`harbor_effective`
already establish elsewhere in this repo. `provisioning.image_factory.registry.schematic.registry`,
if set, still bypasses this entirely — an external registry this repo doesn't manage, unchanged from
before.

**4. Harbor push credentials for Image Factory are explicitly out of scope here.** Setting
`registry.driver: harbor` on a fleet that also runs Image Factory does not fully work yet — pushes
401 against Harbor until a robot-account admin-API Job and its Secret exist. Tracked as
an immediate, named follow-up, not silently left broken without acknowledgment.

## Consequences

- **Two registries can still coexist, on purpose**, the same way ADR-0008 already accepted: a fleet
  can run `registry.driver: harbor` for its own general-purpose registry while Image Factory's
  schematic/cache pushes stay broken until decision 4 ships — named explicitly rather than silently
  regressing a previously-working (if anonymous) push path. Confirmed live: `windsor install` against
  the real local cluster correctly retargeted `image-factory`'s ConfigMap at
  `harbor.registry.svc.cluster.local` (proving the `registry_effective` cross-facet read works) and
  Flux correctly pruned the old bare `registry` StatefulSet/Service/NetworkPolicy from `provisioning`
  once removed from that Kustomization's component list — no orphaned resources left behind.
- **The distribution driver's object-store bucket is renamed** `${object_store.prefix}-registry`,
  not `-image-factory` — safe specifically because this bucket is a disposable, rebuildable cache
  (the module's own `force_destroy` default), so a one-time rename-and-recreate costs nothing real.
- **`provisioning.image_factory.registry_size` is retired**, replaced by `registry.distribution.storage_size`
  — the sizing knob now lives on the facet that owns the storage, not the facet that merely consumes it.
- **The workstation CPU-sizing heuristic** (`config-workstation.yaml`, base 5 + 1 per addon) now
  always counts `registry` for any fleet running Image Factory, since Image Factory can no longer be
  "alone" from registry's perspective — a real, intentional cost increase for the default path,
  reflecting that Image Factory always needed a registry, it just used to hide that cost.

## Alternatives considered

**Migrate Image Factory straight onto Harbor, no second driver.** Rejected: forces every Image
Factory user into Harbor's full cost (Postgres, bucket, admin password, Trivy) for a single internal
consumer that never needed any of it, and produces a narrower fix than the driver generalization —
Harbor push credentials would still need building either way.

**Keep Image Factory's registry entirely separate, do nothing.** Rejected: leaves the exact gap
ADR-0008 named as a phasing consequence permanently unaddressed, and keeps a second, redundant place
in this repo that knows how to run a bare OCI store.

**Ship the Harbor robot-account credential wiring in the same change.** Rejected purely for
review-size and risk reasons — it's genuinely separate machinery (new RBAC, a new admin-API Job
shape none of this repo's existing Jobs need), not a reason to hold back the driver generalization,
which stands on its own and is fully tested (blueprint tests, kustomize builds, and a live
`windsor install` against the real cluster).
