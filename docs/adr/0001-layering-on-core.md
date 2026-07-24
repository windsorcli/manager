---
title: "ADR-0001: What Manager authors and what it turns on in Core"
description: "Manager references Core as a source, so both blueprints compose into one set of facets, components, and schema properties. This ADR draws the line: Manager authors only what a fleet needs, turns Core capabilities on through context values rather than redeclaring them, takes component names Core does not use, and adds only new schema keys. The composer sorts facets by source depth, so composing after Core needs nothing from Manager."
---

# ADR-0001: What Manager authors and what it turns on in Core

## Status

Proposed (2026-07-22). Amended 2026-07-24 after the composer gaps this ADR worked around
were fixed upstream.

## Context

Manager is a blueprint that references Core as a source. Every other Manager ADR
depends on where the boundary sits, so it is worth writing down before any of the
services in the [roadmap](../roadmap-v0.1.0.md) get built.

Composition merges the two blueprints into one set. As of CLI `main` (2026-07-24):

- **A referencing blueprint's facets compose after its sources' facets.** Source depth sorts
  first; the filename-prefix ordinal — `config-` 100, `platform-`/`provider-` 200
  (`-base` 199), `option-` 300, `addon-` 400 — orders facets within a source. A Manager
  `addon-omni.yaml` lands after every Core facet without Manager setting anything.
- **`ordinal:` is author-settable**, on the facet and on individual terraform, kustomize,
  config, and flux entries (`api/v1alpha1/facet_types.go`). It reorders within a source.
- **A blueprint that lists sources loads its own facets too.**
- **Component names are one namespace.** `dependsOn` resolves against the merged set, and a
  name that doesn't resolve fails composition outright, naming the excluded facet and the
  condition that excluded it.
- **Schemas merge, with rules.** `properties` union recursively where both sides are
  `type: object`; `$defs` is replaced wholesale; validation keywords merge conservatively, so
  one fragment cannot loosen a constraint another set. The constraints are written out at the
  top of `contexts/_template/schema.yaml`.
- **Config derived by one source's facets is visible to another's**, so a Manager `config-`
  facet can resolve a value Core's facets then read.
- **An unmet `requires` excludes the facet** rather than failing on the spot.

Composition orders the two blueprints but does not police them: nothing stops Manager from
redeclaring what Core owns, which is what the rules below are for.

## Decision

**1. Manager authors only what a fleet needs.** If a single cluster would also want
the capability, it belongs in Core, and the Manager change waits on the Core change.
This is the rule the README already states; this ADR makes it binding on reviews.

**2. Manager turns Core capabilities on through context values.** Where Core already
carries an addon, a Manager context sets it in `values.yaml`. Manager does not
redeclare a Core facet to change its behavior.

**3. Manager components take names Core does not use, and depend on Core's canonical
names.** Core's `<system>-install` / `<system>-resources` pattern continues here.
Where Manager depends on Core, it uses the stable name — `gateway-resources`,
`pki-resources` — not a driver-specific one. Keep Core's type-prefix filenames for
readability; they order facets within Manager, not against Core.

**4. Manager's schema adds only new keys.** No redeclaring a key Core owns, no
`$defs`. The reasoning is in the schema file itself and does not need repeating here.

**5. The core source tracks `latest` during development and is pinned to a released
tag before Manager's first release.** An unpinned source means a Core release can
change a Manager deployment with no Manager commit to show for it, which is
acceptable while nothing is deployed and not acceptable after that.

## Consequences

- Manager stays small. Most of what a management cluster runs is Core's, turned on.
- Push-down costs latency: a Manager feature that needs a Core change waits for a Core
  release, or on `latest` until one lands.
- Layering is the composer's guarantee, not Manager's convention. The cost is that the
  ordering is no longer visible in Manager's own files — a reader has to know source depth
  sorts first.
- Nothing warns on a component-name collision with Core until composition produces the
  wrong graph. Names are cheap to keep distinct; collisions are not.
- The composition behaviour above is carried only on CLI `main`, so CI installs the CLI from
  there rather than a release. Together with tracking Core's `latest`, that means Manager CI
  absorbs Core and CLI breakage as it happens — the intended trade while the blueprint is
  being built out, and the reason point 5 has a deadline attached.
- Depending on a Core component that only exists under some conditions means restating that
  condition, so Manager holds a copy of Core's gating that nothing keeps in sync.

## Alternatives considered

**Vendor Core's facets into Manager.** Removes every ordering and namespace question
by making Manager self-contained, and gives up the reason to reference a source at
all: Core upgrades would become Manager merges.

**Rely on filename prefixes to order Manager against Core.** Reads cleanly and is what Core
does internally, where one repository controls every name. Across two repositories the
prefix says nothing about which source a facet came from, so it cannot express the
layering; source depth does.
