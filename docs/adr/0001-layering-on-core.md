---
title: "ADR-0001: What Manager authors and what it turns on in Core"
description: "Manager references Core as a source, so both blueprints compose into one flat set of facets, components, and schema properties. This ADR draws the line: Manager authors only what a fleet needs, turns Core capabilities on through context values rather than redeclaring them, and reserves an ordinal band so its facets compose after every Core layer. Ordering is derived from the facet filename prefix and not from the source, so layering after Core is a decision Manager has to make explicitly rather than something it gets for free."
---

# ADR-0001: What Manager authors and what it turns on in Core

## Status

Proposed (2026-07-22).

## Context

Manager is a blueprint that references Core as a source. Every other Manager ADR
depends on where the boundary sits, so it is worth writing down before any of the
services in the [roadmap](../roadmap-v0.1.0.md) get built.

Composition does not keep the two blueprints apart. Verified against the CLI at
`v0.8.1`:

- **Facets from every source land in one flat set.** They are ordered by an ordinal
  derived from the facet's *filename prefix* — `config-` 100, `platform-`/`provider-`
  200 (`-base` 199), `option-` 300, `addon-` 400, anything else 0 — with ties broken
  by `metadata.name` (`pkg/composer/blueprint/ordinal.go`,
  `pkg/composer/blueprint/processor.go`). The source a facet came from is not part of
  the sort. A Manager facet named `addon-omni.yaml` ties with Core's `addon-*` facets
  and lands wherever the alphabet puts it.
- **`ordinal:` is author-settable**, on the facet and on individual terraform,
  kustomize, config, and flux entries (`api/v1alpha1/facet_types.go`).
- **Component names are one namespace.** `dependsOn` resolves against the merged set,
  and a name that doesn't resolve fails composition outright — a Hetzner context
  missing its platform facet fails with `terraform component "cni" depends on
  non-existent component "cluster"` rather than anything that names the real cause.
- **Schemas merge, with rules.** `properties` union recursively where both sides are
  `type: object`; every other key is overlay-wins; `$defs` is replaced wholesale. Load
  order between sources is not something to rely on. The constraints are written out
  at the top of `contexts/_template/schema.yaml`.
- **An unmet `requires` excludes the facet** rather than failing on the spot, which is
  how a missing required value turns into a dangling-dependency error further along.

So "layered on top of Core" describes intent, not a mechanism. Nothing in composition
keeps Manager's contributions behind Core's, and nothing stops Manager from
redeclaring what Core owns.

## Decision

**1. Manager authors only what a fleet needs.** If a single cluster would also want
the capability, it belongs in Core, and the Manager change waits on the Core change.
This is the rule the README already states; this ADR makes it binding on reviews.

**2. Manager turns Core capabilities on through context values.** Where Core already
carries an addon, a Manager context sets it in `values.yaml`. Manager does not
redeclare a Core facet to change its behavior.

**3. Manager facets set an explicit `ordinal:` of 500 or higher.** Filename prefixes
alone do not put Manager behind Core, and depending on `metadata.name` sorting across
two repositories is not a contract anyone can see. Keep Core's type-prefix naming for
readability, and state the ordinal. A facet that genuinely has to compose earlier sets
its own lower value and says why in a comment.

**4. Manager components take names Core does not use, and depend on Core's canonical
names.** Core's `<system>-install` / `<system>-resources` pattern continues here.
Where Manager depends on Core, it uses the stable name — `gateway-resources`,
`pki-resources` — not a driver-specific one.

**5. Manager's schema adds only new keys.** No redeclaring a key Core owns, no
`$defs`. The reasoning is in the schema file itself and does not need repeating here.

**6. The core source tracks `latest` during development and is pinned to a released
tag before Manager's first release.** An unpinned source means a Core release can
change a Manager deployment with no Manager commit to show for it, which is
acceptable while nothing is deployed and not acceptable after that.

## Consequences

- Manager stays small. Most of what a management cluster runs is Core's, turned on.
- Push-down costs latency: a Manager feature that needs a Core change waits for a Core
  release, or on `latest` until one lands.
- Ordinals are a convention with nothing enforcing them. A composition test that
  asserts Manager's facets land after Core's would close that gap and does not exist
  yet.
- Nothing warns on a component-name collision with Core until composition produces the
  wrong graph. Names are cheap to keep distinct; collisions are not cheap to debug.
- Staying on `latest` means Manager CI absorbs Core breakage as it happens. That is
  the intended trade while the blueprint is being built out, and it is the reason
  point 6 has a deadline attached.

## CLI changes this depends on

Three of the decisions above are working around gaps in the composer rather than expressing
something anyone wanted. Each has an issue open against
[windsorcli/cli](https://github.com/windsorcli/cli), and each would let this ADR get
shorter:

- [cli#3042](https://github.com/windsorcli/cli/issues/3042) — facets from a referencing
  blueprint should compose after their source's facets. Rule 3 exists only because they
  don't. If source depth becomes the primary sort key, Manager stops hand-setting ordinals
  and rule 3 is deleted rather than amended.
- [cli#3043](https://github.com/windsorcli/cli/issues/3043) — schema merge takes validation
  keywords last-write-wins, so a fragment can loosen a constraint another fragment set, and
  which fragment lands last depends on the run. Rule 5 is a convention protecting against
  that; conservative merging would make it enforced instead.
- [cli#3044](https://github.com/windsorcli/cli/issues/3044) — a dangling-dependency error
  names the missing component rather than the facet that was excluded and why. This is what
  makes rule 4 matter more than it should: a name collision or a missing contributor
  surfaces as a confusing error rather than a clear one.

Also open and relevant to how Manager contexts get set up:
[cli#3039](https://github.com/windsorcli/cli/issues/3039) (`windsor init` discards the
context config when a later step fails) and
[cli#3032](https://github.com/windsorcli/cli/issues/3032) (an `env()` function for facet
expressions, which would let the Hetzner token come from the environment instead of a
`secret()` reference).

None of these block the decisions here. They determine whether the decisions stay
conventions or become things the tool enforces.

## Alternatives considered

**Vendor Core's facets into Manager.** Removes every ordering and namespace question
by making Manager self-contained, and gives up the reason to reference a source at
all: Core upgrades would become Manager merges.

**Rely on filename prefixes for ordering.** Reads cleanly and is what Core does
internally, where one repository controls every name. Across two repositories the tie
break is alphabetical on `metadata.name`, which no reader would predict and no test
would catch.
