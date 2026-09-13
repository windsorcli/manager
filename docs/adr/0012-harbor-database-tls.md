---
title: "ADR-0012: Harbor's Postgres connection gets real TLS verification"
description: "ADR-0008 flagged Harbor's CNPG connection as running with sslmode: disable, since Harbor's chart has no database-specific CA field the way Keycloak's operator CR does. It turns out the chart does have a CA mechanism — a global caBundleSecretName that injects a CA into core/jobservice/registry/trivy's shared trust store — but it mounts the whole named Secret with no key restriction, and CNPG's own generated CA Secret carries the private signing key alongside the public cert. A new admin-API-shaped Job extracts just the certificate into a dedicated Secret Harbor can safely reference. Getting the sequencing right took a real, live-confirmed lesson: Flux's Helm controller fails an upgrade outright — and rolls it back — when a Deployment stalls waiting on a Secret, rather than tolerating it the way a bare Kubernetes object would, so the extraction has to be a genuine dependency Harbor's own Kustomization waits on, not just a component applied alongside it."
---

# ADR-0012: Harbor's Postgres connection gets real TLS verification

## Status

Proposed (2026-09-13). Depends on [ADR-0008](0008-harbor.md) decision 2, which this closes:
"ships without `sslmode=verify-full`'s CA validation until that gap is confirmed closeable;
revisit once the exact `existingSecret` key contract Harbor's chart expects is confirmed
against the pinned chart version, not paraphrased docs." Both are now confirmed, against the
real pinned chart source, not docs.

## Context

**The `existingSecret` key contract is fine as-is.** Harbor's chart (1.19.2) expects the
Secret named by `database.external.existingSecret` to carry a key literally named `password`
— CNPG's own auto-generated app-credentials Secret (`harbor-db-app`) already uses that exact
key name. Nothing to change there; ADR-0008's doubt was unfounded once checked against the
real chart source instead of paraphrased docs.

**The CA-bundle gap is real, but the chart isn't as bare as ADR-0008 assumed.** There's no
database-specific CA field, but the chart does have a global `caBundleSecretName` that injects
a CA into the shared trust store for core, jobservice, registry, and trivy — the exact
mechanism `sslmode: verify-full` needs to validate CNPG's self-signed cluster CA. Core's own
Keycloak facet already does the equivalent thing through the Operator's own `truststores:`
field, importing `keycloak-db-ca` (CNPG's standard `<cluster-name>-ca` naming) for the same
`sslmode=verify-full` posture — confirming both the mechanism and the naming convention this
ADR reuses for `harbor-db`.

**Harbor's mechanism is coarser than Keycloak's, and that coarseness matters.** The chart's
`caBundleVolume` helper mounts the *entire* Secret named by `caBundleSecretName` with no key
restriction (`subPath: ca.crt` narrows what one container sees, but the pod's own Secret volume
still holds every key from that Secret). CNPG's auto-generated CA Secret carries `ca.crt` *and*
`ca.key` — the CA's private signing key — in one Secret. Pointing `caBundleSecretName` straight
at `harbor-db-ca` would put that private key on the node's tmpfs for Harbor's own pods, not
just the public cert. Nothing in this repo has needed to split a keypair Secret into a
cert-only one before, though the shape isn't new — Core's own private-CA facet keeps
`private-ca-keypair` and `private-ca-trust-cert` as two separate Secrets for exactly this
reason.

**A same-Kustomization Job doesn't survive Helm's own stall detection.** The first version of
this fix put the CA-extraction Job in the same `registry-install` Kustomization as Harbor's own
HelmRelease, reasoning that Kubernetes' own tolerance for a Pod waiting on a not-yet-existing
Secret volume would let everything eventually converge once the Job caught up — the same
"boots fine before the target exists" posture this repo already uses for Omni and Image
Factory's own soft dependencies. Confirmed live that this is wrong for this case specifically:
Flux's Helm controller does not wait indefinitely — it detected `Deployment/harbor-core` as
`Failed` (stalled) and rolled the release back to the previous revision before the extraction
Job even finished, undoing the change entirely. A bare Kubernetes Job or Deployment would have
just kept retrying; a HelmRelease's own upgrade-stall detection does not extend the same
patience.

## Decision

**1. `registry.harbor.gc`-style admin-API Job, `harbor/db-tls`, copies `ca.crt` out of
`harbor-db-ca` into a new cert-only Secret `harbor-db-ca-cert`.** Same-namespace RBAC only
(read one Secret by name, write another) — simpler than `harbor/image-factory`'s cross-namespace
case, since both Secrets live in `registry`.

**2. Harbor's HelmRelease sets `database.external.sslmode: verify-full` and
`caBundleSecretName: harbor-db-ca-cert`** — never the raw `harbor-db-ca` Secret.

**3. The extraction runs in its own Kustomization, `registry-database`, that Harbor's own
Kustomization (`registry`) genuinely `dependsOn` — not a component applied alongside it in the
same one.** `registry-database` depends only on `database-install` (Core's CNPG operator);
`registry` depends on `registry-database-install` in addition to its existing conditional
dependencies. This is the fix for the stall-detection finding above: Flux won't even attempt to
apply Harbor's HelmRelease until the CA cert already exists.

## Consequences

- Harbor's Postgres connection now gets both encryption and certificate/hostname validation,
  closing the gap named in [ADR-0008](0008-harbor.md) decision 2's Consequences.
- `registry-database` needed an explicit `path: registry` — a differently-named flux entry
  doesn't inherit the kustomize path of the facet's other entries, it defaults to a path
  matching its own name. Caught immediately by a live `ArtifactFailed: kustomization path not
  found` once tested against the real cluster, not by local blueprint tests, which don't
  validate that a named path actually resolves to a real directory.
- Confirmed live end-to-end, not just via passing blueprint tests: `harbor-core`'s own boot log
  reads `sslmode-"verify-full"` followed by a successful migration, and the Harbor API responds
  normally afterward.
- Splitting the Kustomization graph this way is now the reference shape for any future
  Manager-owned service that needs something to exist and be ready *before* its own HelmRelease
  reconciles, not just eventually alongside it.

## Alternatives considered

**Point `caBundleSecretName` directly at CNPG's own `harbor-db-ca` Secret.** Rejected — puts
the CA's private signing key on Harbor's own pods for no reason, the exact split Core's own
private-CA facet already avoids for its own keypair.

**`sslmode: require` or `verify-ca` instead of `verify-full`, skipping hostname validation.**
Rejected as a smaller win for no real savings — the CA-extraction Job is the same amount of
work either way, and `verify-full` is what Keycloak's own precedent in this fleet already uses.

**Keep the CA-extraction Job in the same Kustomization as Harbor's HelmRelease, accept the
first-apply race.** Rejected once confirmed live that this isn't just a slower convergence —
it's a hard Helm upgrade failure and rollback, not something that resolves itself on retry
without a forced re-reconcile.
