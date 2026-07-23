# Manager v0.1.0

A management cluster that can provision and operate downstream clusters. Core underneath,
Omni driving Talos, Keycloak as the identity provider, OpenBao holding secrets and the PKI
root. Deployed on Hetzner, previewable locally.

Everything below is a decision to be made in an ADR before it is built. ADRs live in
`docs/adr/NNNN-<slug>.md` and follow the format used in
[core](https://github.com/windsorcli/core/tree/main/docs/adr): frontmatter, Status, Context,
Decision, Consequences.

## In scope

| # | ADR | What it has to decide |
|---|-----|-----------------------|
| 0001 | Layering on Core | Where the line sits between what Manager authors and what it turns on in Core's `values.yaml`. What gets pushed down into Core instead of being written here. |
| 0002 | Identity | Keycloak topology, realm and client bootstrap, how the OIDC issuer reaches downstream API servers, how the management services consume it. |
| 0003 | Secrets and PKI | OpenBao topology, unseal, PKI root and per-cluster intermediates, how downstream External Secrets controllers authenticate. |
| 0004 | Omni | Pro deployment rather than the single-binary demo: etcd, storage, TLS and SANs, SideroLink exposure, auth against Keycloak. |
| 0005 | Image factory | Self-hosted schematics and installer generation, where images live, the air-gapped path. |
| 0006 | Downstream provisioning | Omni and Cluster API both provision clusters. Which one owns what, and how they coexist. |
| 0007 | Manager's own state | Backup and restore for Omni's etcd, the secrets backend, and the databases. What Velero covers and what it can't. |

0001 comes first; the rest reference it. 0002 and 0003 block 0004, since Omni carries no
local user store and needs a place to keep its secrets.

## Deferred

- **Harbor.** Needed for the disconnected install, not for a first cut that pulls from
  upstream registries.
- **Fleet observability.** Core already runs a per-cluster stack. The aggregation half can
  follow once there is a fleet to aggregate.

## Open questions

- Is Hetzner the only deployed platform for v0.1.0, or does metal need to work at the same
  time?
- Single control plane or HA? A management cluster is a single point of failure either way,
  but it changes the storage and etcd decisions in 0004 and 0007.
- Does Manager manage itself, or is it provisioned out of band and only manages downstream?
- What does the local preview actually run? Omni in pro mode may not fit on a workstation.
