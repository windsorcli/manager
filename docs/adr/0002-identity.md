---
title: "ADR-0002: Identity — where Core's Keycloak ends and the fleet's begins"
description: "Core's `identity` capability (driver keycloak, promoted from the earlier `addons.keycloak` sketch) stands up the server (operator, Keycloak CR, Postgres backend, gateway route), a `platform` realm with a security baseline, an RBAC anchor, OIDC clients for the add-ons Core itself ships, and a consumer-extension contract (`identity_effective.{realm,issuer,backchannel_issuer}`) — all shipped, plus a `cluster.oidc` block that wires the kube-apiserver's own OIDC flags on Talos, falling back to the hosted issuer by default. This ADR draws the identity boundary the same way ADR-0001 drew the layering one: Core owns the server and the platform realm because a single cluster wants hardened SSO too, and Manager consumes Core's contract as just another blueprint — adding a Keycloak client (`KeycloakOIDCClient` or, where the consumer needs group-to-role mapping and OIDC doesn't have it yet — Omni first, see [ADR-0004](0004-omni.md) — `KeycloakSAMLClient`) only for the fleet-only services Core doesn't ship, and distributing the downstream-issuer trust. Manager reuses the platform realm rather than forking its own, which means it can add clients but nothing realm-level: operator kubectl auth, the fleet groups, and upstream IdP federation are all Core's by mechanism. With both Core dependencies now shipped, this cut still has no Manager resource to build — the ADR stands as the boundary record and implementation waits on ADR-0004 (Omni), the first fleet service Manager would client. Secrets are deferred to ADR-0003, and wiring the issuer into downstream machine config is deferred to ADR-0006."
---

# ADR-0002: Identity — where Core's Keycloak ends and the fleet's begins

## Status

Proposed (2026-07-23; updated 2026-08-02 — see the note below). Depends on
[ADR-0001](0001-layering-on-core.md). References [ADR-0003](0003-secrets-and-pki.md) (secrets
and PKI) for where credentials live, and blocks ADR-0004 (Omni, not yet written — see the
[roadmap](../roadmap-v0.1.0.md)), which needs an identity provider before it has a place to
keep users.

Both Core issues this ADR originally waited on have shipped:

- [core#2283](https://github.com/windsorcli/core/issues/2283) — the identity capability, now
  top-level `identity` (not `addons.identity` as originally proposed — Core's `addons`
  flatten, [core#2348](https://github.com/windsorcli/core/issues/2348), landed in between).
  Closed completed 2026-07-30 via
  [core#2312](https://github.com/windsorcli/core/pull/2312): the `platform` realm, its
  hardening baseline, the `platform-admins` RBAC anchor, and Grafana's OIDC client all ship.
  Manager's clients now have a real realm to attach to.
- [core#2286](https://github.com/windsorcli/core/issues/2286) — API-server OIDC
  authentication under `cluster.oidc`. The GitHub issue is still open, but the Talos wiring
  has shipped in the same pass: `config-talos.yaml`'s `talos_common` facet maps
  `cluster.oidc.*` to the kube-apiserver's `--oidc-*` flags, defaulting the issuer and client
  ID to the hosted Keycloak when unset, and layering in `--oidc-ca-file` when `pki` is
  enabled. This is the operator `kubectl` auth decision 2 assigns to Core, and the mechanism
  ADR-0006 will consume to make downstream clusters trust the issuer.

**What this means for this ADR:** every Core dependency named below has landed, but that does
not unblock a Manager build. The only Manager-ownable resource this ADR identifies — a
`KeycloakOIDCClient` for a fleet service Core does not ship — has no service to client until
ADR-0004 (Omni) exists. The boundary this ADR draws is now fully live on Core's side; the
blocker moved from "Core hasn't built the realm" to "Manager has nothing of its own to attach
to it yet." The Context and Decision sections below have been updated to describe what Core
actually shipped (config keys, facet names, tense) rather than the PR 2 plan as originally
proposed; the Decision's boundary reasoning is unchanged.

## Context

A management cluster needs one place its operators sign in, one issuer its services trust,
and one issuer the API servers of every downstream cluster trust for `kubectl`
authentication. Keycloak is that provider. The question this ADR settles is not *whether*
Keycloak — the [roadmap](../roadmap-v0.1.0.md) already fixes that — but how much of it is
Core's and how much is Manager's, and how the fleet-level pieces get authored.

**Core builds the server and the platform realm — both now shipped.** An `identity`
capability lives in Core (facet `addon-identity`, gated on `identity.enabled == true`, driver
`keycloak` by default). PR 1 (Core #2295) shipped first, in namespace `system-identity`:

- the Keycloak operator (`identity-install`), with the CRDs vendored under
  `keycloak-26.7.0` and owned by the `crds:` layer — including `KeycloakRealmImport`,
  `KeycloakOIDCClient`, and `KeycloakSAMLClient`, not just `Keycloak`;
- a Keycloak server CR and its CloudNativePG Postgres cluster (`identity-resources`),
  single-instance by default with a `topology: ha` overlay;
- a gateway `HTTPRoute` (`keycloak/gateway`), because Keycloak is reached over HTTPS
  through the shared cluster gateway. TLS terminates at the gateway; Keycloak serves plain
  HTTP internally with `proxy: xforwarded` and its own ingress disabled.

Enabling it auto-enables the `database.postgres` addon and `requires` the gateway. Its driver
`keycloak` configuration surface is `identity.keycloak.{hostname, image, admin.{username,
password}}` alongside the top-level `identity.{enabled, driver, display_name}`; a driver
`oidc` deployment points at an external issuer instead and hosts nothing. The hostname
defaults to `keycloak.<public_domain || private_domain>`.

**Core's PR 2 — the identity a single cluster needs, not just the server — has shipped too**
(core#2312, closed via core#2283). It is deliberately universal, not fleet-specific. Its
principle: *Core ships the mechanism plus a thin, opt-out baseline, and everything else
extends through the same CRDs.* Concretely, Core built:

- a **`platform` realm** via a single `KeycloakRealmImport` (never `master`), carrying a
  security baseline every deployment wants — `sslRequired: external`, brute-force detection,
  sane token lifetimes, a password policy. The realm name is config: `identity.keycloak.realm`,
  defaulting to `platform`;
- a **`platform-admins` group** mapped to the realm-management admin role as an RBAC anchor —
  the group, not its members;
- **OIDC clients for the add-ons Core itself ships** — Grafana is live today (inferred on
  when `observability.enabled` and `observability.grafana.sso != false`, with a
  credential-copying Job that writes the operator-generated client secret into
  `system-observability`), with the MinIO console and gateway edge auth as the same shape to
  follow;
- a **kube-apiserver OIDC client** (`keycloak/realm/clients/kubernetes`), inferred on when
  `cluster.oidc.enabled == true` — this is the piece core#2286 tracks, described further down;
- a **consumer-extension contract**: `identity_effective.{realm, issuer, backchannel_issuer,
  admin_password}`, with the explicit expectation that *a consumer adds a
  `KeycloakOIDCClient` in the platform realm (or a `KeycloakRealmImport` for its own realm)
  from its own facet* — no Core change, no fork.

This is correct under [ADR-0001](0001-layering-on-core.md) rule 1: a single cluster that
wants hardened SSO for its own dashboards wants the *server, a hardened realm, and clients
for the things Core ships* — so all of that is Core's. Core also settles, on its side, the
client-secret handoff (the operator writes a generated client secret into a Kubernetes
Secret; the consumer reads it via `valueFrom`) and names realm-import drift as a known
limitation to revisit with keycloak-config-cli — both mechanisms Manager inherits rather
than reinvents.

**What is left for the fleet is a short list — and it turns out to be shorter than it
first looks.** A client for each fleet service Core does not ship (Omni first), and the
distribution of downstream-cluster trust in the issuer. Those are Manager's. Operator
`kubectl` auth is *not* — it is realm-level infrastructure a single cluster would also want,
so it goes to Core (decision 2); and the fleet groups and federation are not Manager's to
author either, because they live inside the realm import Core owns (decision 7). So the
boundary is not "server here, everything else there"; it is the ADR-0001 line exactly:
**Core owns everything a single cluster needs (server + platform realm + baseline + realm-level
infrastructure + core-add-on and kubectl clients + the contract); Manager is one more consumer
of that contract, adding only clients for the fleet services Core does not ship.** The rest of
this ADR is how Manager consumes it — and why, for now, there is almost nothing to build.

## Decision

**1. Core owns the server and the platform realm; Manager is a consumer of Core's contract.**
Manager turns the server on the way ADR-0001 rule 2 requires — a context's `values.yaml`
sets `identity.enabled: true`, and where a management cluster wants it, the top-level
`topology: ha` and an explicit `identity.keycloak.hostname`. Manager never redeclares
`addon-identity`, and it does not stand up a realm: it reuses the realm Core builds. Manager
authors, as new facets that compose on
top, only the pieces the fleet adds — OIDC clients for services Core does not ship, and the
downstream-trust distribution. This is the same relationship any consuming blueprint has to
Core; Manager is not privileged, it is just the first consumer.

**2. Manager reuses Core's `platform` realm rather than forking its own.** Core's plan asks,
as an open question, whether consumers are comfortable adding clients to the platform realm
instead of always standing up their own — and from the Manager side the answer is yes.
Operators and management services live in the one realm Core already hardens
(`identity.keycloak.realm`, default `platform`). What Manager adds to that realm is a Keycloak
client per **fleet service Core does not ship** — Omni (ADR-0004) is the first; later a fleet
dashboard or fleet API is the same shape. Group membership drives role, and the
group-claim-to-RBAC mapping is the contract every consumer reads — which client CRD gets that
mapping is a per-consumer choice: Omni's OIDC provider has no group-claim mapping yet, so
[ADR-0004](0004-omni.md) uses `KeycloakSAMLClient` for it instead, with `KeycloakOIDCClient`
as the default for anything that supports OIDC claim mapping natively (Core's own add-on
clients all do). One realm keeps operator identity in one place and inherits Core's security
baseline for free.

Two things that look like they belong here do not. **Operator `kubectl` auth is Core's, not
Manager's** — the `kubectl`/`kubelogin` OIDC client is realm-level infrastructure a single
cluster would also want (ADR-0001 rule 1), so it lands in Core's platform-realm baseline
alongside `platform-admins`, and Core also owns wiring an API server to trust the issuer —
shipped as [core#2286](https://github.com/windsorcli/core/issues/2286) (API-server OIDC under
`cluster.oidc`, Talos wiring in `config-talos.yaml`'s `talos_common` facet), keeping the
client and the flags that make it useful in one place rather than split across repositories.
And the **fleet operator groups are not Manager's to author** — see decision 7.
**A separate per-fleet realm is the named successor**: when a second tenant or a hard
isolation boundary actually exists, Manager stands up its own realm through the same
`KeycloakRealmImport` path Core's contract already invites — this decision is revisited, not
worked around. There is one tenant today, so there is one realm.

**3. Manager's clients bootstrap declaratively through the operator's `KeycloakOIDCClient`,
not Terraform — for the first cut.** The operator and its client CRDs are already present, so
a client is just another CR reconciled under Flux, in the same GitOps path as everything
else, with no admin credential needed at plan time and no "Keycloak must be reachable before
Terraform can configure it" ordering problem during `windsor up`. Manager inherits Core's
client-secret handoff wholesale: the operator writes the generated client secret into a
Kubernetes Secret, and the consumer reads it via `valueFrom`. Its cost is the same one Core
names for the realm — the operator reconciles a client on create but does not fully manage
drift on every field afterward — and it is acceptable for clients whose shape changes rarely.
**The Terraform Keycloak provider is the named successor**: when per-client lifecycle
management, rotation, or drift detection becomes the actual problem, fleet identity moves to a
Terraform module Windsor already knows how to compose, and this decision is revisited — not
worked around. Core and Manager move together here, because the drift limitation is one they
share.

**4. The issuer is the public gateway hostname Core already publishes, served under a
publicly-trusted certificate.** Downstream API servers set
`--oidc-issuer-url=https://keycloak.<domain>/realms/platform` — the same issuer Core derives
and exposes as config — and a group claim, and authenticate operators through `kubelogin`.
Trust is the subtle part: an API server that does not trust the issuer's TLS cert rejects
every token. Serving the issuer under a publicly-trusted cert (the gateway's ACME path) makes
downstream trust zero-config. The private-PKI alternative — the issuer under Manager's own
root, distributed to every downstream API server as `--oidc-ca-file` — is deferred to
ADR-0003, which owns the root and its distribution. v0.1.0 assumes the public-cert path.

**5. Secrets come from ADR-0003, not from here.** The bootstrap admin credential and every
client secret are held in the secrets backend ADR-0003 defines and surfaced with External
Secrets — this ADR does not invent a parallel secrets story. The interim is the mechanism
Core already relies on: the operator-generated initial admin secret, and operator-written
client secrets consumed via `valueFrom`, with ESO layered on once it exists. Nothing in this
ADR is blocked on that interim, but the fleet is not production until 0003 is.

**6. Manager's identity facets follow ADR-0001's mechanics exactly.** Component names Core
does not use, and `dependsOn` on Core's canonical tier names — a client waits on
`identity-resources` (the
server and the platform realm must exist before a client can attach to the realm), and any
client that needs the gateway route waits on `gateway-resources`, the same names Core's own
facet depends on. Manager's schema adds only new keys under a new path (fleet client
configuration), reads `identity.keycloak.realm` (or `identity_effective.realm`) from Core's
contract rather than redefining it, and never redeclares `identity`.

**7. Reusing the realm means Manager can only add client-shaped resources; everything
realm-level is Core's, by mechanism as well as by layer.** The operator's CRDs split cleanly:
`KeycloakOIDCClient` and `KeycloakSAMLClient` are standalone CRs a consumer can add to an
existing realm, but a realm's groups, its upstream identity-provider federation, its users,
and its custom flows all live *inside* the single `KeycloakRealmImport` — and that import is
Core's. So decision 2's "reuse the platform realm" carries a hard consequence: Manager can
add fleet **clients**, and nothing else. It cannot author a fleet operator group, broker the
realm to a corporate IdP, or seed users, because there is no CR for those separate from the
realm Core owns.

This surfaces a contradiction in Core's plan worth naming: Core lists *upstream federation*
and *users* as **consumer-owned**, yet the mechanism it ships — one Core-owned realm import —
gives a consumer no way to contribute them. Closing that needs one of two things, neither in
this ADR's scope: Core **parameterizes** its realm import to accept consumer-supplied groups
and identity providers (the realm stays one, Core stays its owner, consumers feed it values),
or Manager takes the **separate-realm successor** from decision 2 and owns a realm import of
its own. Until one of those exists, fleet federation and fleet groups are blocked, and this
ADR does not pretend otherwise.

**8. Wiring the issuer into downstream clusters is ADR-0006's job, not this one.** Getting
`--oidc-issuer-url` and any `--oidc-ca-file` into a downstream cluster's Talos or kubeadm
machine config is downstream-provisioning work. This ADR fixes only the stable contract
those clusters consume: the issuer URL, the realm name, and the group claim. ADR-0006 and
ADR-0004 (Omni, which authenticates against this realm) build on that contract.

## Consequences

- Manager's identity footprint is far smaller than a first reading of "the fleet's identity
  provider" suggests: it turns Core's server on and adds a `KeycloakOIDCClient` per fleet
  service Core does not ship. The realm, its baseline, the RBAC anchor, the `kubectl` client,
  every core-add-on client, and everything else realm-level are Core's. Most of Keycloak —
  including most of the identity — is Core's.
- **This cut still builds nothing, but the reason has changed.** Once `kubectl` moved to Core
  (decision 2) and everything realm-level was found to be structurally Core's (decision 7),
  the only Manager-ownable resource left is a client for a fleet service Core does not ship —
  and the first of those, Omni, is ADR-0004. Both of Core's dependencies (PR 2 / core#2283 and
  the `cluster.oidc` wiring / core#2286) have now shipped (2026-07-25 through 2026-07-30), so
  the wait is no longer on Core — it is entirely on ADR-0004 being written. This ADR stands as
  the boundary record until then; the exploratory build on this branch was dropped rather than
  merged empty, and there is still nothing to resurrect it into.
- Manager's original ordering dependency on Core's PR 2 —
  [core#2283](https://github.com/windsorcli/core/issues/2283), landed via
  [core#2312](https://github.com/windsorcli/core/pull/2312) — is now cleared: the server, the
  `platform` realm, the `identity.keycloak.realm` config key (renamed from the `addons.keycloak`
  sketch this ADR originally cited), and the exposed `identity_effective.issuer` are all
  shipped. Manager's clients have a real realm to attach to; nothing about identity blocks a
  future Manager facet from Core's side anymore.
- The operator's reconcile-on-create-only limitation is a known, bounded debt that Core and
  Manager share — Core for the realm, Manager for its clients. It buys a working GitOps-native
  bootstrap now; it will not manage identity whose shape churns. Decision 3 names the exit
  (Terraform), and Core names the same one (keycloak-config-cli), so this does not become a
  silent trap on either side.
- Reusing the platform realm couples the fleet's operator identity to Core's realm hardening:
  Manager gets `sslRequired`, brute-force detection, and token-lifetime defaults for free, but
  also inherits them — a fleet that needed a materially different realm posture would be the
  trigger for the separate-realm successor in decision 2, not a set of overrides on Core's
  realm.
- The public-certificate assumption in decision 4 makes v0.1.0 depend on the gateway's ACME
  path working for the Keycloak hostname. A disconnected or private-only deployment does not
  have that and waits on ADR-0003's CA-distribution path — the same deferral Harbor and the
  air-gapped install already carry in the roadmap.
- Identity now sits on the critical path of a `windsor up`: Core's realm depends on the
  server, Manager's service clients depend on the realm, and Omni (ADR-0004) depends on all of
  it. A slow or failed Keycloak converge blocks more than its own namespace. The dependency
  chain is explicit (decision 6), so a failure names its cause rather than surfacing as a
  dangling dependency elsewhere.
- Two ADRs are now entangled by design: 0002 owns the fleet clients, 0003 owns the
  secrets they need. Neither is complete alone, and 0004 waits on both — which is exactly the
  ordering the roadmap already states.

## Alternatives considered

**Manage identity entirely with the Terraform Keycloak provider from the start.** Full
lifecycle management, drift detection, and rotation, in the language Windsor already
compiles to. Rejected for the first cut on the bootstrapping order: the provider needs a
reachable Keycloak and an admin credential at plan time, but Keycloak comes up inside the
same `windsor up` that would configure it, so a fresh install has a chicken-and-egg the
declarative CRDs do not. It is the successor in decision 3, not a rejected idea — only
deferred until its cost is worth paying.

**Stand up a separate fleet realm instead of reusing Core's `platform` realm.** A dedicated
realm (working name `windsor`) would isolate fleet operator identity from the single-cluster
platform realm and give Manager full ownership of realm lifecycle and posture. Rejected for
v0.1.0 as premature isolation: there is one tenant (the fleet operator) and a small, fixed set
of management services, so a second realm is bootstrap and hardening Manager would own and
duplicate for no isolation anyone needs yet — while Core's platform realm already ships the
baseline. Core's contract explicitly supports a consumer `KeycloakRealmImport`, so this is the
named successor in decision 2, reachable without a Core change the day a second tenant or a
hard boundary exists.

**Have Core build the fleet clients too.** Since Core already builds the realm and its own
add-on clients, it could also client Omni and the API servers and hand Manager a fully wired
realm. Rejected under ADR-0001 rule 1, from the other direction: Omni, the management API
server, and downstream `kubectl` trust are things only a fleet needs, and pushing them into
Core would make Core carry fleet concerns and depend on add-ons it does not ship. Core draws
its own line at "clients for the add-ons Core ships"; everything past that line is a consumer's,
and Manager is the consumer.

**A realm per management service.** Stronger isolation between services. Rejected as premature
for the same reason as a separate fleet realm: a small, fixed set of management services sharing
one hardened realm with group-driven roles is enough and far less to bootstrap. Multi-realm is a
change to make when isolation is actually required, and decisions 2 and 6 do not foreclose it.

**Skip Keycloak and trust each cloud's OIDC provider directly.** Downstream API servers
could trust a managed IdP (Entra, Google) and skip self-hosting. Rejected because the fleet
must work on metal and Hetzner where there is no such provider, because Omni (ADR-0004)
carries no user store of its own and needs somewhere to point, and because a self-hosted
issuer is the only one that survives the disconnected install the roadmap commits to.
