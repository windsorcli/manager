# Manager

Manager is a Windsor blueprint for a management cluster. It layers on top of
[Core](https://github.com/windsorcli/core), which brings up the Kubernetes platform, and
adds the services that provision and operate a fleet of downstream clusters.

Like Core, it compiles to plain Terraform and Kustomize.

Open source under [MPL 2.0](LICENSE). Drive it with the [Windsor CLI](https://github.com/windsorcli/cli).
Documentation at [windsorcli.dev](https://windsorcli.dev).

## What it installs

Manager is a work in progress. The services it targets:

- **[Omni](https://github.com/siderolabs/omni)**, self-hosted — Talos cluster management,
  deployed in production mode rather than the single-binary demo.
- **[Talos image factory](https://github.com/siderolabs/image-factory)** — self-hosted image
  and installer generation for air-gapped and version-pinned fleets.
- **Cluster API** — declarative provisioning and lifecycle for workload clusters.
- **[Keycloak](https://www.keycloak.org)** — single sign-on across the management services,
  and the OIDC issuer downstream API servers trust for `kubectl` authentication.
- **[OpenBao](https://openbao.org)** — secrets backend and PKI root: dynamic credentials,
  per-cluster intermediate CAs, and the store downstream External Secrets controllers read.
- **[Harbor](https://goharbor.io)** — container registry with image signing, scanning, and
  replication. Also serves the blueprint artifacts in a disconnected install.
- **Fleet observability** — long-term metric storage, a central log sink, and one
  [Grafana](https://grafana.com) across the fleet.
- **[Velero](https://velero.io)** — scheduled backup and restore, for downstream workloads
  and for Manager's own state: Omni's etcd, Harbor's database, the secrets backend.

## Quick start

### Preview it locally

You can preview the manager locally by running `windsor up` in a new repository. You'll need
[Terraform](https://developer.hashicorp.com/terraform/install) and Docker, Docker Desktop, or
[Colima](https://github.com/abiosoft/colima).

```bash
git init manager-preview && cd manager-preview
windsor init local
windsor up
```

The blueprint will bootstrap in around 5-8 minutes depending on your hardware resources.

In order to connect to local URLs, run the following in a privileged shell (it will prompt for `sudo`)

```bash
windsor configure network
```
You can then browse local services at `https://omni.test`, or `https://harbor.test`, and so on. Refer to their documentation for more information.
To tear down the local environment, run `windsor down`

### On a real platform

On real infrastructure you run `windsor bootstrap` instead of `up`. This example uses Hetzner
Cloud.

```bash
windsor init mgmt --platform hetzner \
  --set hetzner.location=fsn1 \
  --set hetzner.network_zone=eu-central \
  --set dns.public_domain=mgmt.example.com \
  --set email=platform@example.com
```

`--set` writes these into `contexts/mgmt/values.yaml`. Add your Hetzner API token to the same
file as a secret reference.

```yaml
hetzner:
  token: ${secret("Developer", "hetzner", "token")}
```

```bash
windsor bootstrap mgmt
```

`bootstrap` applies the components in order and waits until every Kustomization is ready. From
there, `windsor apply` reconciles any changes you make.
To tear down the deployment, run `windsor destroy --confirm=mgmt`

## License

[Mozilla Public License 2.0](LICENSE).

## Contributing

Format, test, and scan with `task fmt`, `task test`, and `task scan`. Install the git hooks
with `lefthook install`. Tooling versions are pinned in [aqua.yaml](aqua.yaml).
