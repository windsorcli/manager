---
title: "ADR-0001: What Manager authors and what it turns on in Core"
description: "Manager references Core as a source, so both blueprints compose into one set of facets, components, and schema properties. This ADR draws the line: Manager authors only what a fleet needs and turns Core capabilities on through context values rather than redeclaring them. Layering after Core used to be something Manager had to buy with hand-set ordinals; the composer now sorts by source depth, so it comes for free and the ordinal rule is gone."
---

# ADR-0001: What Manager authors and what it turns on in Core

## Status

Proposed (2026-07-22). Amended 2026-07-24: most of the composer gaps this ADR was working
around have landed in the CLI. The old rule 3 (hand-set ordinals) is deleted outright, and
the remaining rules lean less on convention than they did — though none of them is fully
tool-enforced, so they still bind on review. See
[CLI changes this depends on](#cli-changes-this-depends-on) for what landed and what has not.

## Context

Manager is a blueprint that references Core as a source. Every other Manager ADR
depends on where the boundary sits, so it is worth writing down before any of the
services in the [roadmap](../roadmap-v0.1.0.md) get built.

Composition merges the two blueprints into one set. As of CLI `main` (2026-07-24):

- **A referencing blueprint's facets compose after its sources' facets.** Source depth is
  the primary sort key ([cli#3042](https://github.com/windsorcli/cli/issues/3042)), with the
  filename-prefix ordinal — `config-` 100, `platform-`/`provider-` 200 (`-base` 199),
  `option-` 300, `addon-` 400 — ordering facets *within* a source. So a Manager
  `addon-omni.yaml` lands after every Core facet without Manager saying anything. This is
  the mechanism rule 3 used to substitute for by hand.
- **A blueprint that lists sources still loads its own facets**
  ([cli#3048](https://github.com/windsorcli/cli/issues/3048)). Before that fix, listing any
  source silently loaded none of the blueprint's own facets, which Manager worked around by
  naming itself as an extra `template` source in each context.
- **`ordinal:` is still author-settable**, on the facet and on individual terraform,
  kustomize, config, and flux entries (`api/v1alpha1/facet_types.go`). It is no longer needed
  to layer after a source, only to reorder within one.
- **Component names are one namespace.** `dependsOn` resolves against the merged set, and a
  name that doesn't resolve fails composition outright — but the error now names the facet
  that was excluded and the condition that excluded it
  ([cli#3044](https://github.com/windsorcli/cli/issues/3044)), so a missing contributor
  reads as its own cause rather than as a dangling component somewhere downstream.
- **Schemas merge, with rules.** `properties` union recursively where both sides are
  `type: object`; `$defs` is replaced wholesale. Validation keywords now merge
  *conservatively* ([cli#3043](https://github.com/windsorcli/cli/issues/3043)), so one
  fragment can no longer silently loosen a constraint another fragment set — which used to
  depend on which fragment happened to land last. The constraints are written out at the top
  of `contexts/_template/schema.yaml`.
- **Config derived by one source's facets is visible to another's**
  ([cli#3050](https://github.com/windsorcli/cli/issues/3050)), so a Manager `config-` facet
  can resolve a value that Core's facets then read.
- **An unmet `requires` excludes the facet** rather than failing on the spot.

So "layered on top of Core" is now a mechanism rather than only an intent. What composition
still does not do is stop Manager from redeclaring what Core owns — that stays a review
concern, and it is what the rules below are for.

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
readability; ordering after Core is the composer's job now, not the filename's.

**4. Manager's schema adds only new keys.** No redeclaring a key Core owns, no
`$defs`. The reasoning is in the schema file itself and does not need repeating here.

**5. The core source tracks `latest` during development and is pinned to a released
tag before Manager's first release.** An unpinned source means a Core release can
change a Manager deployment with no Manager commit to show for it, which is
acceptable while nothing is deployed and not acceptable after that.

*(A previous rule 3 required every Manager facet to set an explicit `ordinal:` of 500 or
higher. [cli#3042](https://github.com/windsorcli/cli/issues/3042) made source depth the
primary sort key, so the ordinals were removed and the rule deleted rather than amended.)*

## Consequences

- Manager stays small. Most of what a management cluster runs is Core's, turned on.
- Push-down costs latency: a Manager feature that needs a Core change waits for a Core
  release, or on `latest` until one lands.
- Layering is now the composer's guarantee rather than Manager's convention, so there is
  nothing left to enforce with a test and nothing to get wrong by forgetting an ordinal.
  What Manager gives up is the ability to see the ordering in its own files: the reason a
  facet lands where it does is now upstream behaviour, so a reader has to know that source
  depth sorts first.
- Nothing warns on a component-name collision with Core until composition produces the
  wrong graph. Names are cheap to keep distinct; collisions are not cheap to debug — though
  a *missing* contributor now names itself, so only true collisions stay hard.
- Staying on `latest` means Manager CI absorbs Core and CLI breakage as it happens. That is
  the intended trade while the blueprint is being built out, and it is the reason
  point 5 has a deadline attached. It cuts both ways: the fixes this amendment relies on
  arrived the same way.

## CLI changes this depends on

Most of what this ADR was working around has landed. Closed and released into CLI `main`:

- [cli#3042](https://github.com/windsorcli/cli/issues/3042) — a referencing blueprint's
  facets now compose after its sources'. **Rule 3 deleted**; the `ordinal:` lines came out of
  both Manager facets, and the composed blueprint is byte-identical without them.
- [cli#3048](https://github.com/windsorcli/cli/issues/3048) — a blueprint that lists sources
  now loads its own facets. The `template` self-reference came out of every Manager context's
  `blueprint.yaml`.
- [cli#3043](https://github.com/windsorcli/cli/issues/3043) — validation keywords merge
  conservatively, so rule 4 is enforced by the tool instead of protected by convention.
- [cli#3044](https://github.com/windsorcli/cli/issues/3044) — dangling-dependency errors name
  the excluded facet and its condition, so rule 3 no longer carries the debugging burden it
  did.
- [cli#3039](https://github.com/windsorcli/cli/issues/3039) — `windsor init` keeps the context
  config when a later step fails.
- [cli#3032](https://github.com/windsorcli/cli/issues/3032) — an `env()` function for facet
  expressions, with [cli#3069](https://github.com/windsorcli/cli/issues/3069) adding env
  support to test cases. This is what would let the Hetzner S3 credentials come from the
  environment instead of the placeholders each context carries today; that change has not
  been made yet.

Still open, and still shaping how Manager is written:

- [cli#3047](https://github.com/windsorcli/cli/issues/3047) — `dependsOn` has no optional
  form, so a cross-source dependency has to restate the upstream's own enabling condition.
  This is why `addon-image-factory` carries
  `"${gateway.enabled == true ? 'gateway-install' : ''}"` rather than naming
  `gateway-install` and letting it drop out.
- [cli#3005](https://github.com/windsorcli/cli/issues/3005) — `Kustomization` has no
  `spec.decryption`, which blocks Flux-native SOPS and so bears on ADR-0003.

None of these block the decisions here.

## Alternatives considered

**Vendor Core's facets into Manager.** Removes every ordering and namespace question
by making Manager self-contained, and gives up the reason to reference a source at
all: Core upgrades would become Manager merges.

**Rely on filename prefixes for ordering.** Reads cleanly and is what Core does
internally, where one repository controls every name. This was rejected when the tie break
across two repositories was alphabetical on `metadata.name` — something no reader would
predict and no test would catch. It is no longer a live alternative: source depth sorts
first, and the prefix now orders facets within a source, which is the job it is good at.
