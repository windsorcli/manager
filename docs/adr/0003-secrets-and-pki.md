---
title: "ADR-0003: Secrets and PKI — the fleet's store, root, and who authenticates to what"
description: "Core is proposing, not building, the two pieces this depends on: a secrets-store addon (OpenBao, core#2285) and a runtime secret-sync controller (External Secrets Operator, core#2284) — both open issues, neither with a facet yet. Core's own scoping already draws half the boundary: OpenBao's PKI engine is explicitly out of that issue, and per-fleet policy and roles are explicitly named as Manager's to build. This ADR draws the rest, the same way ADR-0002 drew identity's: Core owns the store and the controller because a single cluster wants runtime secrets too, and Manager owns everything fleet-only — the PKI engine that makes the management cluster a certificate authority for its downstream clusters, the per-cluster intermediates it issues, the auth method that lets a downstream cluster's ESO reach across cluster boundaries to read from it, and the bootstrap secret (OpenBao's unseal key) that has to exist before ESO does. That last piece reuses a mechanism this repo already has — a Terraform-generated key held in state and placed by a facet's own `secrets:` block, the same shape as the image factory's signing key — rather than inventing a new one. Nothing here is buildable yet; both Core issues are open and unbuilt, so this stands as the boundary record, same as ADR-0002 did before Core's identity work landed."
---

# ADR-0003: Secrets and PKI — the fleet's store, root, and who authenticates to what

## Status

Proposed (2026-07-31). Depends on [ADR-0001](0001-layering-on-core.md). Referenced by
[ADR-0002](0002-identity.md) for where Keycloak's admin credential and client secrets live,
and for the private-PKI alternative to the public-certificate OIDC issuer. Blocks ADR-0004
(Omni, not yet written — see the [roadmap](../roadmap-v0.1.0.md)), which needs somewhere to
keep its own secrets before it can run in anything but demo mode.

Unlike ADR-0002, this ADR is written entirely ahead of the Core work it depends on: neither
[core#2284](https://github.com/windsorcli/core/issues/2284) (External Secrets Operator) nor
[core#2285](https://github.com/windsorcli/core/issues/2285) (OpenBao as a secrets store) has
a facet yet — both are open proposals. This stands as the boundary record for when they land,
the same role ADR-0002 played before Core's identity PR 2 shipped.

## Context

The roadmap states this ADR's job in one line: *"OpenBao topology, unseal, PKI root and
per-cluster intermediates, how downstream External Secrets controllers authenticate."* That
sentence is actually two different problems wearing one name.

**Runtime secrets is the ordinary problem, and Core already owns most of it.** Core computes
build-time secrets today — `secret()` resolves through the providers under the top-level
`secrets:` block and lands in generated values — but nothing syncs a live credential into a
running cluster. core#2284 fills that gap with External Secrets Operator, install-only,
because *"every cluster runs it, standalone or not, regardless of what store sits behind
it."* core#2285 fills the other half, a self-hosted OpenBao instance backing it, because
*"self-hosting the store is the whole point for an airgapped or single-cluster install."*
Both issues predate Core's `addons` flatten
([core#2348](https://github.com/windsorcli/core/issues/2348)); their sketched shapes
(`addons.external_secrets`, `addons.secrets_store`) will presumably land top-level instead,
matching `identity` and `database`. Neither changes the boundary either way.

**PKI is the problem Core's own issue explicitly declines to own.** core#2285 says so
directly: *"The PKI engine is a natural follow-on... Out of scope here; filing this as the
secrets store only."* And separately, core#2284 defers the `ClusterSecretStore` itself —
the thing that actually binds ESO to a backing store — to the OpenBao issue, which in turn
says fleet-level *"policies and roles"* are Windsor Manager's to configure *"as its own
facet."* Core's own scoping, unprompted, draws most of this ADR's line already.

Core's existing `pki` addon (cert-manager, trust-manager, and named `ClusterIssuer`s —
`private-selfsigned`, `private-ca`, `public-selfsigned`, `public-acme`) is real, built, and
irrelevant to the hard part here. It issues certificates *within* one cluster from a root
that cluster holds itself. Nothing about it lets a management cluster act as a certificate
authority *for* other clusters — that capability doesn't exist anywhere in either repo yet.

ADR-0002 already wrote two checks against this ADR that have to clear:

- Decision 4: the private-PKI alternative to the public-certificate OIDC issuer — *"the
  issuer under Manager's own root, distributed to every downstream API server as
  `--oidc-ca-file` — is deferred to ADR-0003, which owns the root and its distribution."*
- Decision 5: *"The bootstrap admin credential and every client secret are held in the
  secrets backend ADR-0003 defines and surfaced with External Secrets."*

"Owns the root and its distribution" and "downstream provisioning wires machine config is
ADR-0006's job" (ADR-0002 decision 7) read like a contradiction until they're read as two
different verbs: this ADR owns *producing* the root and *making it available as data* —
config a consumer can read, a Secret a consumer can mount. Getting that data into a specific
downstream node's Talos or kubeadm machine config is ADR-0006's mechanical problem, the same
split ADR-0002 already drew for the issuer URL itself.

## Decision

**1. Core owns the store and the controller; Manager owns everything fleet-only.** Applying
[ADR-0001](0001-layering-on-core.md) rule 1 exactly: a standalone cluster legitimately wants
a self-hosted secrets store and runtime secret sync — Core's own issues say so — so OpenBao
and External Secrets Operator are Core's, turned on through context values once they exist,
never redeclared. What a single cluster never needs: a PKI engine that issues certificates
*to other clusters*, or a way for *another cluster's* ESO to authenticate across the
boundary. Those are fleet questions, and they're Manager's.

**2. Manager configures OpenBao's PKI secrets engine; Core's OpenBao does not have one.**
core#2285 draws this line itself. Manager mounts a `pki` secrets engine in Core's OpenBao
instance, holding the fleet's root CA, and a per-downstream-cluster mount or role issuing
that cluster's intermediate — the standard OpenBao/Vault hierarchy (mount a root, issue
scoped intermediates, never hand out the root key itself). v0.1.0 holds the root inside
OpenBao rather than under an offline root of its own; splitting the root out is the named
successor once that trust model is the actual problem, not a v0.1.0 requirement — Windsor
has one management cluster to secure, not a certificate authority business.

**3. The unseal secret is generated once by Terraform and placed the way the image
factory's signing key already is — because ESO can't be the thing that unseals OpenBao.**
OpenBao needs its unseal material before it will serve anything, which means before ESO can
sync a single Secret out of it — the same bootstrap-ordering problem ADR-0002 hit with
Keycloak's admin credential, solved the same way. `terraform/keys/signing` already
generates a key once, holds it in state, and a facet `secrets:` block places it via
`terraform_output(...)` — no ESO, no runtime dependency on the thing being bootstrapped.
The unseal key (or, for OpenBao's newer recovery-key auto-unseal path, the equivalent
recovery material) follows the identical shape: a new `keys/unseal`-style Terraform module,
placed by Manager's own facet the way `image-factory-cache-signing-key` is today. This is
reuse, not a new mechanism — worth stating plainly because it would be easy to reach for
Vault's usual answer (cloud KMS auto-unseal) and quietly drop metal and Hetzner, which the
roadmap does not get to do.

**4. Downstream ESO authenticates to Manager's OpenBao through OpenBao's Kubernetes auth
method, one mount per downstream cluster.** A downstream cluster's ESO holds no static
credential Manager would have to distribute and rotate; instead, Manager registers each
downstream cluster's own API server (its token-review endpoint and signing keys) as a
distinct Kubernetes auth mount in OpenBao, and binds a role to it scoped to only that
cluster's secrets. Nothing crosses the boundary except a token the downstream cluster's own
API server already vouches for. This is a fleet-only registration Manager performs per
cluster as it provisions one — Core's OpenBao has no notion of "other clusters" to begin
with.

**5. Manager exposes the root and issuer contracts as data; getting them into a specific
downstream node is ADR-0006's job.** This ADR is responsible for the fleet root existing,
for intermediates being issuable, and for publishing them as something a consumer can read
— mirroring ADR-0002's `identity_effective` contract. It is not responsible for the
mechanics of injecting a CA bundle into a Talos or kubeadm machine config; that continues to
be downstream-provisioning work, unchanged from where ADR-0002 decision 7 already put it.

**6. Nothing here is buildable before Core ships core#2284 and core#2285.** Unlike every
other decision in this ADR, this one has no interim. ADR-0002 could lean on the
operator-generated admin secret and `valueFrom` while ESO didn't exist yet; there is no
equivalent fallback for "the secrets backend itself doesn't exist." Manager's facets for
decisions 2 through 5 wait on both Core issues landing, the same way the identity facets
waited on Core's PR 2.

## Consequences

- This ADR is smaller than the roadmap's one-line description suggested, once Core's own
  issue scoping is taken at face value: Core owns the store, the controller, and ordinary
  runtime secrets — genuinely most of "secrets." Manager's remainder is real but narrow: a
  PKI engine, per-cluster intermediates, cross-cluster auth mounts, and one bootstrap key.
- The dependency runs one direction and is currently unmet: both core#2284 and core#2285 are
  open, unbuilt issues. This ADR cannot be implemented today, only designed against. That is
  a stronger form of the same wait ADR-0002 had on Core's PR 2 — there, a published server
  with nothing in it was at least something to turn on; here, there is nothing to turn on
  yet at all.
- Reusing the `keys/signing` pattern for the unseal secret means the fleet's root of trust
  for *secrets* is itself secured by the same mechanism as a boot-asset signing key — a
  Terraform state file. That is an appropriate v0.1.0 answer, not a permanent one; anyone
  auditing the fleet's security posture should be pointed at this decision explicitly rather
  than discovering it by reading `terraform/keys/`.
- Per-downstream-cluster Kubernetes auth mounts mean OpenBao's own configuration grows one
  mount and one role per cluster Manager provisions — this is fleet-management surface area
  Core never has to think about, and Manager now owns registering and de-registering it as
  clusters come and go, which ADR-0006 (downstream provisioning) will need to drive.
- Splitting "the root exists" (this ADR) from "the root reaches a machine config" (ADR-0006)
  repeats the exact seam ADR-0002 drew for the OIDC issuer. Consistent, but it means a
  reader has to hold both ADRs to see the full downstream-trust story for either identity or
  secrets — noted here so it isn't rediscovered as a surprise.

## Alternatives considered

**Cloud KMS auto-unseal, matching Vault's own most common answer.** Removes the
Terraform-state-held-key question entirely on AWS, Azure, or GCP. Rejected as the default
because it does not exist on Hetzner or bare metal, which the roadmap commits to, and this
ADR should not produce a fleet that only auto-unseals on clouds the roadmap already treats
as one option among several. Worth offering as a per-platform override once a cloud KMS is
actually reachable, not as the only path.

**A single shared credential for every downstream cluster's ESO, rather than a
Kubernetes-auth mount per cluster.** Far less OpenBao configuration to manage. Rejected: one
shared secret handed to every downstream cluster is one leak away from every cluster's
secrets, and revoking a single compromised or decommissioned downstream cluster means
rotating a credential every other cluster also holds. Per-cluster mounts cost more
configuration and buy isolation that a fleet, as opposed to a single cluster, actually needs
— the same reasoning ADR-0002 applied to per-downstream-cluster OIDC trust.

**An offline root CA, with OpenBao holding only an intermediate.** The security-conscious
default for a PKI hierarchy of any real size, and the natural next step once this matters.
Rejected for v0.1.0 as premature relative to the fleet's actual size: an offline root adds a
ceremony (generating, signing, and re-sealing an air-gapped root) that a single management
cluster issuing intermediates to a handful of downstream clusters does not yet justify.
Named as the successor in decision 2, not ruled out.

**Wait for Core to build core#2284/#2285 before writing this ADR at all.** Keeps the ADR
grounded entirely in shipped code, the way most of ADR-0001 was. Rejected because ADR-0002
proved the opposite order works: writing the boundary first meant Manager's identity facets
were ready the moment Core's realm shipped, rather than starting the design conversation
only after. The cost is stated plainly in decision 6 rather than hidden: this ADR has no
interim to fall back on while it waits.
