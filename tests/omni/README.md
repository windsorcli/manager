# Omni SideroLink registration test

Boots a local QEMU Talos VM and registers it with a locally running Omni over
SideroLink — proving `addon-provisioning.yaml`'s omni SideroLink path actually works
end to end, not just that the Helm chart installs. This is a manual/local
verification tool, not part of `task test`.

**Procedure: bring the management cluster up first, then run this against it.**

```bash
windsor up   # once, or whenever the local cluster needs (re)converging

task test:omni -- --join-config ~/Downloads/machine-config.yaml
```

Once it registers, assign it to a cluster and watch it install like any other machine
— that part is a normal Omni UI flow (Clusters → Create Cluster), not something this
script drives.

Tear down when you're done:

```bash
task test:omni -- --clean
```

## Why this exists

Straightforward as it sounds, a plain `docker run` Talos container **cannot** join
Omni — its `PLATFORM=container` mode never brings up the WireGuard client SideroLink
depends on. A real VM is the only thing that works locally, and getting one to
actually complete a SideroLink join against Omni running behind Docker Desktop needed
five separate fixes (DNS, TLS hostname validation, CA trust, the advertised WireGuard
endpoint, and along the way a real bug in `addon-image-factory.yaml`'s installer
registry config). This script automates all of it. The full story — every dead end,
every root cause, every command used to diagnose it — is in
[`docs/spikes/omni-docker-machine-registration.md`](../../docs/spikes/omni-docker-machine-registration.md).
Read that first if something here breaks in a new way.

## Prerequisites

- **macOS with Docker Desktop**, and `windsor up` already converged against the
  `local` context. This script's DNS and endpoint-reachability workarounds are
  specific to Docker Desktop's networking model — see the spike doc for what a
  Linux/CI equivalent would need instead (untested, likely different).
- **Not colima.** Confirmed broken, not just untested: colima's cluster and this
  script's QEMU VM each get their own `vmnet-shared` network segment, and
  `vmnet.framework` doesn't route between separate `vmnet-shared` segments at all —
  confirmed with `tcpdump`, no packets cross over regardless of host routes or
  `ip.forwarding`. Verifying the gateway-routed WireGuard path on colima needs a
  different approach (e.g. a WireGuard test client running as a Pod inside the
  cluster) — not attempted by this script.
- **A machine join config**, downloaded from Omni's own UI: sign in, then Home →
  "Download Machine Join Config". This is the one manual step. Omni's join tokens
  aren't reachable headlessly without a pre-provisioned `omnictl` service account, and
  setting one up isn't worth it for a local script — a browser click is simpler and
  more honest about what a real operator does. Defaults to
  `~/Downloads/machine-config.yaml` if `--join-config` is omitted.
- **`sudo` access.** `talosctl`'s QEMU provisioner needs root for CNI bridge
  networking and Hypervisor.framework acceleration. Expect one prompt per VM
  (re)create.

## What it actually does

1. Fetches this cluster's self-signed Private CA directly from Kubernetes — no manual
   step. The gateway's TLS cert is issued by it, and a bare VM has no reason to trust
   it otherwise.
2. Appends a `TrustedRootsConfig` document to the downloaded join config so CA trust
   rides along with the SideroLink join in one push — Talos's maintenance-mode `apid`
   only accepts one config push per boot, so everything has to land together.
3. Stands up a small, additive DNS responder bound to the QEMU bridge's own gateway
   address (`10.6.0.1` by default), answering `*.test` with that address instead of
   the loopback Windsor's own `dns.test` hardcodes (correct only for the Mac itself —
   useless for a VM in a different network namespace). Forwards everything else
   upstream, since the VM's own Kubernetes bootstrap needs to resolve
   `registry.k8s.io` too.
4. Boots a QEMU VM from a plain Talos ISO in maintenance mode and pushes the
   assembled config to it.
5. Leaves the VM running — it has to stay up to remain registered — and tells you
   where to check on it.

## Flags

```
--join-config PATH    path to Omni's downloaded machine-config.yaml
                       (default: ~/Downloads/machine-config.yaml if it exists)
--name NAME            talosctl cluster name (default: omni-siderolink-test)
--cidr CIDR            /24 CIDR for the QEMU bridge network (default: 10.6.0.0/24 -
                       chosen to avoid colliding with windsor-local's 10.5.0.0/16)
--talos-version VER    Talos version to boot (default: matches the installed
                       talosctl client)
--clean                tear down a previous run's VM and DNS override, then exit
-h, --help             show the full usage/background text
```

## Troubleshooting

- **`exec: "talosctl-darwin-<arch>": executable file not found in $PATH`** — your
  `talosctl` install is a shim (e.g. aqua's `aqua-proxy`) whose real binary `sudo`
  can't see, because `sudo` doesn't inherit the shim's own resolved `$PATH`. This
  script deliberately doesn't work around a specific install method's internals — find
  the real binary's directory yourself (for aqua: `dirname "$(aqua which talosctl)"`)
  and add it to root's `PATH` (e.g. via `visudo`'s `secure_path`, or by running this
  script with `sudo -E env PATH="<that dir>:$PATH" tests/omni/register-machine.sh
  ...`). Installing `talosctl` via Homebrew directly avoids this entirely.
- **`ports are not available: ... 0.0.0.0:6443 ... address already in use`** on your
  *next* `windsor up` — this script's own load balancer can squat on host port 6443
  if the VM wasn't cleaned up first. Run `task test:omni -- --clean` before touching
  `windsor up` again.
- **`rpc error: code = AlreadyExists desc = etcd data directory is not empty`** on
  `windsor up`, unrelated to this script's own VM — `windsor up` appears to
  unconditionally recreate `controlplane-1` on every invocation, which then collides
  with Terraform's `talos_machine_bootstrap` resource against the container's
  persisted disk. A `windsor down && windsor up` clears it; see the spike doc's
  "Operational incident" section. Not caused by or specific to this script.
- **Stuck on `x509: certificate signed by unknown authority`** — the cluster's
  Private CA rotates on every full `windsor down && windsor up`. Just re-run this
  script; it fetches the CA fresh every time.
- **Join token rejected (`PermissionDenied desc = unauthorized`)** — the downloaded
  `machine-config.yaml` is stale (usually because the cluster got recreated since you
  downloaded it). Re-download it from Omni's UI and pass the fresh path.
