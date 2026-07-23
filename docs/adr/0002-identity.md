---
title: "ADR-0002: Identity — where Core's Keycloak ends and the fleet's begins"
description: "Core's Keycloak addon stands up the server (operator, Keycloak CR, Postgres backend, gateway route) and — in its PR 2 plan — a `platform` realm with a security baseline, an RBAC anchor, OIDC clients for the add-ons Core itself ships, and a consumer-extension contract (realm name + issuer URL as readable config). This ADR draws the identity boundary the same way ADR-0001 drew the layering one: Core owns the server and the platform realm because a single cluster wants hardened SSO too, and Manager consumes Core's contract as just another blueprint — adding a KeycloakOIDCClient only for the fleet-only services Core doesn't ship (Omni first) and distributing the downstream-issuer trust. Manager reuses the platform realm rather than forking its own, which means it can add clients but nothing realm-level: operator kubectl auth, the fleet groups, and upstream IdP federation are all Core's by mechanism. Because kubectl moved to Core and Omni is ADR-0004, this cut has no Manager resource to build yet — the ADR stands as the boundary record and implementation waits on Core's PR 2. Secrets are deferred to ADR-0003, and wiring the issuer into downstream machine config is deferred to ADR-0006."
---

# ADR-0002: Identity — where Core's Keycloak ends and the fleet's begins

## Status

Proposed (2026-07-23). Depends on [ADR-0001](0001-layering-on-core.md). References
[ADR-0003](../roadmap-v0.1.0.md) (secrets and PKI) for where credentials live, and blocks
[ADR-0004](../roadmap-v0.1.0.md) (Omni), which needs an identity provider before it has a
place to keep users.

## Context

A management cluster needs one place its operators sign in, one issuer its services trust,
and one issuer the API servers of every downstream cluster trust for `kubectl`
authentication. Keycloak is that provider. The question this ADR settles is not *whether*
Keycloak — the [roadmap](../roadmap-v0.1.0.md) already fixes that — but how much of it is
Core's and how much is Manager's, and how the fleet-level pieces get authored.

**Core builds the server (shipped) and the platform realm (planned).** A `keycloak` addon
is landing in Core (facet `addon-keycloak`, gated on `addons.keycloak.enabled == true`). PR 1
(Core #2295) shipped, in namespace `system-identity`:

- the Keycloak operator (`identity-install`), with the CRDs vendored under
  `keycloak-26.7.0` and owned by the `crds:` layer — including `KeycloakRealmImport`,
  `KeycloakOIDCClient`, and `KeycloakSAMLClient`, not just `Keycloak`;
- a Keycloak server CR and its CloudNativePG Postgres cluster (`identity-resources`),
  single-instance by default with a `topology: ha` overlay;
- a gateway `HTTPRoute` (`keycloak/gateway`), because Keycloak is reached over HTTPS
  through the shared cluster gateway. TLS terminates at the gateway; Keycloak serves plain
  HTTP internally with `proxy: xforwarded` and its own ingress disabled.

Enabling it auto-enables the `database.postgres` addon and `requires` the gateway. Its
configuration surface today is four keys — `addons.keycloak.{enabled, driver, hostname,
image}`. The hostname defaults to `keycloak.<public_domain || private_domain>`.

**Core's PR 2 plan does not stop at the server — it builds the identity a single cluster
needs.** Core's keycloak-idp plan (in the `core` repo, `docs/plans/keycloak-idp.md`) takes the
server the rest of the way to a working provider, and it is deliberately universal, not
fleet-specific. Its principle: *Core ships the mechanism plus a thin, opt-out baseline, and
everything else extends through the same CRDs.* Concretely, Core will build:

- a **`platform` realm** via a single `KeycloakRealmImport` (never `master`), carrying a
  security baseline every deployment wants — `sslRequired: external`, brute-force detection,
  sane token lifetimes, a password policy. The realm name is config: `addons.keycloak.realm`,
  defaulting to `platform`;
- a **`platform-admins` group** mapped to the realm-management admin role as an RBAC anchor —
  the group, not its members;
- **OIDC clients for the add-ons Core itself ships** — Grafana first (the reference
  `generic_oauth` integration), then the MinIO console, then gateway edge auth — each gated
  on its add-on being enabled;
- a **consumer-extension contract**: the realm name and the derived issuer URL
  (`https://<keycloak-hostname>/realms/<realm>`) exposed as readable config, with the explicit
  expectation that *a consumer adds a `KeycloakOIDCClient` in the platform realm (or a
  `KeycloakRealmImport` for its own realm) from its own facet* — no Core change, no fork.

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
sets `addons.keycloak.enabled: true`, and where a management cluster wants it, `topology: ha`
and an explicit `hostname`. Manager never redeclares `addon-keycloak`, and it does not stand
up a realm: it reuses the realm Core builds. Manager authors, as new facets that compose on
top, only the pieces the fleet adds — OIDC clients for services Core does not ship, and the
downstream-trust distribution. This is the same relationship any consuming blueprint has to
Core; Manager is not privileged, it is just the first consumer.

**2. Manager reuses Core's `platform` realm rather than forking its own.** Core's plan asks,
as an open question, whether consumers are comfortable adding clients to the platform realm
instead of always standing up their own — and from the Manager side the answer is yes.
Operators and management services live in the one realm Core already hardens
(`addons.keycloak.realm`, default `platform`). What Manager adds to that realm is a
`KeycloakOIDCClient` per **fleet service Core does not ship** — Omni (ADR-0004) is the first;
later a fleet dashboard or fleet API is the same shape. Group membership drives role, and the
group-claim-to-RBAC mapping is the contract every consumer reads. One realm keeps operator
identity in one place and inherits Core's security baseline for free.

Two things that look like they belong here do not. **Operator `kubectl` auth is Core's, not
Manager's** — the `kubectl`/`kubelogin` OIDC client is realm-level infrastructure a single
cluster would also want (ADR-0001 rule 1), so it lands in Core's platform-realm baseline
alongside `platform-admins`, provided Core also owns wiring an API server to trust the issuer.
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

**6. Manager's identity facets follow ADR-0001's mechanics exactly.** Ordinal `500` or
higher (matching `addon-image-factory`), component names Core does not use, and
`dependsOn` on Core's canonical tier names — a client waits on `identity-resources` (the
server and the platform realm must exist before a client can attach to the realm), and any
client that needs the gateway route waits on `gateway-resources`, the same names Core's own
facet depends on. Manager's schema adds only new keys under a new path (fleet client
configuration), reads `addons.keycloak.realm` from Core's contract rather than redefining it,
and never redeclares `addons.keycloak`.

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
- **This cut builds nothing yet, so the branch is parked.** Once `kubectl` moved to Core
  (decision 2) and everything realm-level was found to be structurally Core's (decision 7),
  the only Manager-ownable resource left is a client for a fleet service Core does not ship —
  and the first of those, Omni, is ADR-0004. There is no fleet client to author until then.
  This ADR therefore stands as the boundary record; the implementing facets wait on both
  Core's PR 2 and ADR-0004, and the exploratory build on this branch was dropped rather than
  merged empty.
- Manager depends on Core's PR 2, not just PR 1. The server is shipped; the `platform` realm,
  the `addons.keycloak.realm` config key, and the exposed issuer URL are still planned. Until
  Core's PR 2 lands, Manager's clients have no realm to attach to. This is an ordering
  dependency across the two repos, and it is one-directional: Core's plan does not need
  anything from Manager, so it can proceed independently, and Manager's identity facets are
  gated behind it.
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
