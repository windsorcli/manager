# Manager

Manager is a Windsor blueprint for standing up a management cluster. It layers on
top of [Core](https://github.com/windsorcli/core): Core brings up the Kubernetes
platform — CNI, GitOps, certificates, storage, observability — and Manager adds
the control-plane services that operate a fleet of downstream clusters.

Like Core, Manager compiles to plain Terraform and Kustomize. Nothing proprietary
runs in the deployed infrastructure; Manager is only present at build time. Each
release is tested end to end and its upgrade path is validated in CI before it
ships.

Open source under [MPL 2.0](LICENSE). Drive it with the [Windsor CLI](https://github.com/windsorcli/cli).
Documentation at [windsorcli.dev](https://windsorcli.dev).

## What it installs

Manager is built out progressively. The target set of management services:

- **Self-hosted [Omni](https://github.com/siderolabs/omni)** — Talos cluster
  management, provisioned for a production ("pro") deployment rather than the
  single-binary demo mode.
- **[Talos image factory](https://github.com/siderolabs/image-factory)** —
  self-hosted image and installer generation for air-gapped and pinned fleets.
- **[Harbor](https://goharbor.io)** — container registry with image signing,
  scanning, and replication.
- **Cluster API** — declarative provisioning and lifecycle of workload clusters.

Further services are added as the blueprint matures.

## Composition

A Windsor blueprint is a Terraform stack plus Kubernetes manifests, parameterized
by conditional fragments called *facets*. A facet declares a `when` expression and
the Terraform inputs and Kustomize overlays it contributes when that condition
holds. Manager references Core as a source and adds its own facets, terraform
modules, and kustomize add-ons on top.

```
manager/
├── kustomize/    cluster resources
├── terraform/    infrastructure
└── contexts/     per-environment configuration
    ├── _template/
    └── <context>/
```

Each context has a `values.yaml` describing intent, validated against
`contexts/_template/schema.yaml`. Facets translate that intent into the specific
Terraform inputs and Kustomize overlays that realize it.

Initialize a context: `windsor init mgmt --platform metal`.

## License

[Mozilla Public License 2.0](LICENSE).

## Contributing

Format, test, and scan with `task fmt`, `task test`, and `task scan`. Install the
git hooks with `lefthook install`. Tooling versions are pinned in [aqua.yaml](aqua.yaml).
