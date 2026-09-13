---
title: "ADR-0011: A Harbor robot account for image factory, closing the gap ADR-0010 named"
description: "ADR-0010 generalized the registry capability but left registry.driver: harbor genuinely broken for a fleet also running Image Factory: Harbor requires authenticated push, and Image Factory's chart has no credential field of its own for it. This ADR closes that gap with a new admin-API Job — the first one in this repo that also needs Kubernetes RBAC, since the credential Secret it writes has to land in Image Factory's own provisioning namespace, not registry. Two real Harbor API behaviors surfaced only by testing against the live API, not the swagger spec: POST /robots silently ignores a client-supplied secret and always generates its own, and an unscoped GET /robots only ever returns system-level robots — project-level ones need an explicit Level+ProjectID query."
---

# ADR-0011: A Harbor robot account for image factory, closing the gap ADR-0010 named

## Status

Proposed (2026-09-13). Depends on [ADR-0010](0010-registry-distribution-driver.md) (the
`registry_effective` cross-facet config this Job's consumer, Image Factory, already reads) and
[ADR-0008](0008-harbor.md) (the `registry` facet and its admin-API Job pattern). Closes
[#207](https://github.com/windsorcli/manager/issues/207).

## Context

ADR-0010 left one gap open by design: `registry.driver: harbor` plus Image Factory enabled
correctly points Image Factory at Harbor's hostname and project, but every push 401s — Harbor
requires an authenticated principal, and Image Factory's chart has no values-level credential
field for its own outbound pushes at all. Confirmed live at the time: `HEAD .../manifests/...:
unexpected status code 401 Unauthorized`.

**The credential has to land in a different namespace than every other admin-API Job writes
to.** Every existing Job in this repo (`harbor/oidc`, `harbor/proxy-cache`, `harbor/gc`) writes
Secrets in its own `registry` namespace, read by workloads in that same namespace. This Job's
target credential is read by Image Factory's own pod, which lives in `provisioning`. Writing a
Secret there needs Kubernetes RBAC this repo has never needed before — every prior Job is a pure
HTTP client against Harbor's API, with no Kubernetes API access at all.

**The chart's own credential mechanism is ambient, not a values field.** Image Factory's chart
(`ghcr.io/siderolabs/charts/image-factory` 1.7.0) has no `config.artifacts.*.auth` surface —
its outbound OCI client (`go-containerregistry`) reads credentials the same way `docker`/`crane`
do: a `~/.docker/config.json`-shaped file, located via the `DOCKER_CONFIG` environment variable
when set. The chart's generic `extraVolumes`/`extraVolumeMounts`/`env` fields are the way to
wire that in, matching a `kubernetes.io/dockerconfigjson` Secret's own key name
(`.dockerconfigjson`) remapped to `config.json` on the way into the pod.

**Two Harbor API behaviors only surfaced by testing against the real API, not the swagger
spec.** Both cost real debugging time and are worth recording so nobody re-derives them:

1. `POST /robots` silently ignores a client-supplied `secret` in the request body and always
   generates its own — confirmed by sending one value and getting a different one back in
   `RobotCreated.secret`. The swagger's own description ("The secret of the robot") reads like
   an input field; it isn't, for creation. `PATCH /robots/{id}` (refresh), by contrast, *does*
   honor a client-supplied secret. The fix reads the real secret back from the create response
   rather than trusting what was sent.
2. An unscoped `GET /robots` (no query) only ever returns system-level robots — Harbor's own
   handler defaults `Level=system, ProjectID=0` when no `Level` keyword is in the query string.
   Finding a project-level robot needs the exact combined query `q=Level=project,ProjectID=<id>`
   in one string; passing `Level` and `ProjectID` as separate query values, or omitting either,
   silently returns an empty list with no error.

## Decision

**1. A new admin-API Job, `harbor/image-factory`, creates a dedicated `image-factory` Harbor
project and a scoped push/pull robot account, then writes a `kubernetes.io/dockerconfigjson`
Secret into `provisioning`.** Idempotent the same way every other Job here is: if the target
Secret already exists, exit immediately without calling Harbor at all. If not, and a matching
robot already exists (found via the `Level=project,ProjectID=<id>` query), refresh its secret
via `PATCH` rather than creating a duplicate; only create fresh when no robot exists yet.

**2. The Job's own ServiceAccount lives in `registry` (alongside every other admin-API Job); a
`Role`/`RoleBinding` in `provisioning` grants that ServiceAccount permission to manage exactly
one named Secret there — cross-namespace, the first RBAC resource any Job in this repo has
needed.** `create` can't be scoped by `resourceNames` (the object doesn't exist yet at
authorization time); `get`/`update`/`patch` are scoped to the one Secret name.

**3. Image Factory's HelmRelease gets a new `harbor-auth` Component, active only when
`registry_effective.driver == 'harbor'`, mounting that Secret and setting `DOCKER_CONFIG`.** No
change needed for the `distribution` driver — it stays anonymous, as it always was.

**4. Schematic and installer paths get a driver-aware default namespace, unifying everything
under one Harbor project.** Harbor requires at least a `project/repo` path — a bare repository
name isn't valid — so the installer's previous hardcoded empty namespace (harmless against the
bare `distribution` store, invalid against Harbor) now resolves to `image-factory` for the
harbor driver, the same project cache already defaults to. Schematic's own namespace default
(`siderolabs/image-factory`) is untouched for the `distribution` driver, but resolves to
`image-factory` for harbor too, so the whole factory — schematic, cache, installer — pushes into
one project the one robot account covers, rather than needing two.

## Consequences

- Removed the schema `default: siderolabs/image-factory` on
  `provisioning.image_factory.registry.schematic.namespace` — it permanently masked the facet's
  own `??` fallback (a schema default is never null, so the driver-aware ternary downstream
  never ran). The same gotcha [ADR-0008](0008-harbor.md)'s Consequences already documented for
  cross-facet `when:` visibility, here biting a same-facet `??` expression instead. The
  installer's own namespace key was added with no schema default from the start, confirming the
  fix by never exhibiting the bug.
- This is the first Job in this repo with Kubernetes RBAC beyond the default ServiceAccount —
  worth a second look if a future admin-API Job ever needs the same shape, rather than
  reinventing the Role/RoleBinding split from scratch.
- Confirmed live end-to-end: a real schematic POST returns `201`, and the resulting
  `image-factory/schematics` repository shows up in Harbor with a real artifact — not just a
  config-wiring check.

## Alternatives considered

**Reuse the shared `harbor-admin-password` credential for Image Factory's pushes instead of a
scoped robot account.** Rejected: spreads the admin credential to a workload that only ever
needs push/pull on one project, the opposite of every other credential-handling decision in this
repo (Harbor's own admin-API Jobs never leak that password to a workload Secret, only to
themselves).

**Delete-and-recreate an orphaned robot instead of refreshing its secret.** Rejected once the
refresh endpoint was confirmed to work correctly — recreating churns the robot's ID and audit
history for no benefit over a secret rotation in place.

**Keep the schematic project at `siderolabs/image-factory` for the harbor driver too, accepting
two Harbor projects and a two-scope robot.** Rejected as needless complexity: nothing outside
Image Factory's own bookkeeping reads this path, so unifying it under one project is free and
means one project, one robot, not two of each.
