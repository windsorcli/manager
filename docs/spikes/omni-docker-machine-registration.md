---
title: "Spike: registering a local Talos machine against Omni (Docker, then QEMU)"
description: "Test procedures and results for joining a container-based and a QEMU-based Talos machine to a local Omni instance over SideroLink — QEMU succeeds end to end."
---

# Spike: registering a local Talos machine against Omni

Status: spike, carried out 2026-08-06. **Result: success**, via QEMU — including full
downstream cluster formation (etcd, Kubernetes API, `Running`), not just SideroLink
registration. The whole flow (DNS override, CA fetch, VM boot, config push) is now
automated: `task test:omni` (see
[`tests/omni/README.md`](../../tests/omni/README.md)). This document is the "why" —
read it when that script breaks in a new way, or before touching a Linux/CI variant of
it (untested; Docker Desktop's networking model, which most of the fixes below work
around, doesn't apply there).

Two approaches tried, in order:

1. **Docker container** — negative. SideroLink's WireGuard client never activates in
   Talos's `PLATFORM=container` mode; the machine never appears in Omni.
2. **QEMU VM** — succeeds, once four separate issues are fixed in sequence: DNS
   resolution, TLS hostname/SAN validation, TLS CA trust, and the advertised
   WireGuard endpoint. The machine fully registers, Omni streams its live logs
   through the SideroLink tunnel, and Omni even auto-provisions it into a cluster.
   See [Final conclusion](#final-conclusion).

## Goal

Confirm that a locally running Omni (`addon-omni.yaml`, `workstation.runtime ==
'docker-desktop'`) can be joined by a Talos "machine" running locally, without any
real hardware.

## Attempt 1: Docker container

### What was tried

1. Logged into the local Omni UI (`https://omni.test:8443`) with the dev admin
   account (`dev-admin@local.test` / `admin-password`, seeded by Core's `dev-user`
   component when `dev == true`).
2. Downloaded a machine join config from Omni's home page ("Download Machine Join
   Config"):
   ```yaml
   apiVersion: v1alpha1
   kind: SideroLinkConfig
   apiUrl: https://omni-siderolink.test:8443?jointoken=<token>
   ---
   apiVersion: v1alpha1
   kind: EventSinkConfig
   endpoint: '[fdae:41e4:649b:9303::1]:8091'
   ---
   apiVersion: v1alpha1
   kind: KmsgLogConfig
   name: omni-kmsg
   url: tcp://[fdae:41e4:649b:9303::1]:8092
   ```
   The `fdae:41e4:649b:9303::1` address is Omni's own SideroLink overlay IP, derived
   client-side from the account ID.
3. Rewrote `apiUrl` to dial the manager's own Talos-in-Docker control-plane
   container directly on the shared `windsor-local` Docker network
   (`https://10.5.0.10:30443?jointoken=...`) rather than `omni-siderolink.test:8443`
   — that hostname resolves to `127.0.0.1` from inside a sibling container (Docker
   Desktop's embedded DNS forwards `*.test` back to the Mac's own loopback), which is
   the container's own loopback, not the host's.
4. Booted a bare Talos container in maintenance mode on that same network:
   ```bash
   docker run -d --name talos-fake-machine \
     --network windsor-local \
     -p 50001:50000/tcp \
     --privileged --security-opt seccomp=unconfined \
     --tmpfs /run --tmpfs /system --read-only \
     -e PLATFORM=container \
     ghcr.io/siderolabs/talos:v1.13.5
   ```
5. Pushed the rewritten config:
   ```bash
   talosctl apply-config --insecure --nodes 127.0.0.1:50001 --file siderolink.yaml
   # -> "Applied configuration without a reboot"
   ```

### What happened

- The config was accepted and persisted, but `EventsSinkController` retried
  indefinitely trying to reach Omni's overlay address, failing with `network is
  unreachable`.
- No `siderolink`/`wireguard`-tagged log lines appeared at all — the SideroLink
  WireGuard client never even attempted a connection.
- A sidecar joining the container's netns (`--network container:talos-fake-machine`)
  showed only `lo` and `eth0` — **no WireGuard interface was ever created.**
- Omni's Machines page stayed at "No Machines Found."

### Conclusion

**Containerized Talos (`PLATFORM=container`) does not register with Omni over
SideroLink.** It's a real Talos node for `talosctl`'s own docker-provisioner
orchestration, but its networking stack never brings up the WireGuard client
SideroLink depends on. Omni's own "Getting Started" panel corroborates this — it
suggests `talosctl cluster create qemu`, not Docker, for local testing.

## Attempt 2 & 3: QEMU VM

### Setup

`talosctl`'s QEMU provisioner runs on macOS via Homebrew's `qemu-system-aarch64`, but
needs **root** for CNI bridge networking and Hypervisor.framework acceleration — an
outward-facing, privileged operation run by the user directly, not the agent. Two
non-obvious setup problems came up first:

1. **The `talosctl` on `$PATH` is an aqua shim** that re-execs a same-named helper
   binary (`talosctl-darwin-arm64`) for its load-balancer subprocess, and `sudo`
   doesn't inherit the shim's resolved `$PATH`:
   ```
   exec: "talosctl-darwin-arm64": executable file not found in $PATH
   ```
   Fixed by pointing `$PATH` at aqua's own cache dir for the exact installed version.
2. **`talosctl cluster create qemu`'s newer preset-based subcommand has no
   `--nameservers` override** — needed for the DNS fix below — so the *older*
   `talosctl cluster create --provisioner qemu` interface was used instead, which
   also needs an explicit `--iso-path` (it has no image-factory download step of its
   own; without one it looks for a locally-built `_out/vmlinuz-arm64` that doesn't
   exist outside a Talos source checkout).

Working command shape (`--cidr 10.6.0.0/24` avoids colliding with the existing
`windsor-local` Docker network, `10.5.0.0/16`):

```bash
TALOSCTL_PATH="/Users/ryanvangundy/.local/share/aquaproj-aqua/pkgs/github_release/github.com/siderolabs/talos/v1.13.7/talosctl-darwin-arm64"
TALOSCTL="/Users/ryanvangundy/.local/share/aquaproj-aqua/bin/talosctl"

sudo -E env PATH="$TALOSCTL_PATH:$PATH" "$TALOSCTL" cluster create \
  --provisioner qemu \
  --name omni-spike \
  --controlplanes 1 --workers 0 \
  --cidr 10.6.0.0/24 \
  --nameservers 10.6.0.1 \
  --iso-path ~/.talos/cache/<cached-talos-iso> \
  --skip-injecting-config \
  --wait=false
```

This creates a **real root-owned bridge interface on the Mac** (`bridge100`, gateway
`10.6.0.1`) — not a network nested inside another VM the way Docker Desktop's
containers are, which is what makes the rest of this spike possible.

### Problem 1: DNS

The join config's `apiUrl` needs a hostname matching the gateway's TLS cert SAN
(`*.<domain>`) — a raw IP fails hostname verification outright (see Problem 2). But:

- `dns.test` (the CoreDNS container backing local `*.test` resolution) publishes port
  53 to `127.0.0.1` only (`lsof -iUDP:53` confirms) — unreachable from a VM.
- Even if reachable, its `*.test` answer is a **hardcoded literal `127.0.0.1`** —
  correct only for a client whose own loopback *is* where the service lives.
- The QEMU provisioner's DHCP hands out public resolvers (`8.8.8.8`, `1.1.1.1`) by
  default, with no override on the newer subcommand (see Setup above).

**Fix, no sudo needed:** Docker Desktop's own port-publishing runs through a real
host-level process (`com.docker.backend`, confirmed via `lsof`), not something nested
in nother VM — so a plain `docker run -p <host-ip>:53:53/udp ...` can bind a new
listener on the bridge gateway's own address, additively, without touching
`dns.test`'s existing `127.0.0.1:53` bind:

```bash
docker run -d --name dns-vm-override \
  -p 10.6.0.1:53:53/udp \
  -v /tmp/vm-dns-corefile/Corefile:/etc/coredns/Corefile:ro \
  coredns/coredns:latest -conf /etc/coredns/Corefile
```

with a Corefile answering `*.test` with the bridge address instead of `127.0.0.1`:

```
test:53 {
    template IN A {
        match "^.*\.test\.$"
        answer "{{ .Name }} 60 IN A 10.6.0.1"
    }
}
```

Paired with `--nameservers 10.6.0.1` at VM creation, `talosctl get resolvers
--insecure` on the VM confirmed it actually uses this resolver. **Fully solved.**

### Problem 2: TLS SAN (dialing by IP)

With DNS still unresolved, the first real join attempt (dialing the gateway by
literal IP) failed:

```
x509: cannot validate certificate for 10.6.0.1 because it doesn't contain any IP SANs
```

The gateway's cert only has hostname SANs (`*.<domain>`) — a literal IP was never
going to validate. Once Problem 1 was fixed and the join dialed
`omni-siderolink.test` (now correctly resolving to `10.6.0.1`), this error
disappeared entirely. **Fully solved by fixing DNS.**

### Problem 3: TLS trust (unknown CA)

Past the SAN check, the next error:

```
x509: certificate signed by unknown authority
```

The gateway's cert is issued by this repo's own self-signed `CN=Private CA` (the same
one `4de10cd` wires Omni's own pods to trust). Found and extracted it directly from
the cluster — no browser needed:

```bash
windsor exec -- kubectl get secret -n system-pki-trust private-ca-trust-cert \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > private-ca.crt
openssl verify -CAfile private-ca.crt leaf.pem   # -> OK
```

Talos has a purpose-built maintenance-mode config document for exactly this,
`TrustedRootsConfig`, pushed alongside the `SideroLinkConfig` in the same
`apply-config` call (maintenance mode's insecure `apid` window only accepts one
config push per boot, so everything has to land together):

```yaml
apiVersion: v1alpha1
kind: TrustedRootsConfig
name: private-ca
certificates: |
  -----BEGIN CERTIFICATE-----
  ...
  -----END CERTIFICATE-----
```

**Fully solved.** (This CA rotates on every full cluster recreate — re-extract it
each time, see the [operational incident](#operational-incident) below for why that
came up.)

### Problem 4: the advertised WireGuard endpoint

Past TLS entirely, `siderolink.ManagerController` still never completed:

```
configuring siderolink connection {"peer_endpoint": "127.0.0.1:30180", ...}
```

Omni tells every joining machine to dial `127.0.0.1:30180` for the actual WireGuard
data tunnel — that's `omni_effective.wireguard_advertised_endpoint` in
`addon-omni.yaml`, intentionally the Mac's own loopback for `workstation.runtime ==
'docker-desktop'` (correct for a machine running *on* the Mac, which is the whole
reason that facet publishes it as a Docker Desktop hostport). From inside the VM's
own separate network namespace, `127.0.0.1` means the VM itself — the handshake never
had anywhere real to go.

**Fix:** set `omni.wireguard.advertised_endpoint: 10.6.0.1:30180` in
`contexts/local/values.yaml` (the bridge gateway address, reachable from the VM) and
redeploy. This is a genuine config change to the deployed local Omni, not throwaway
test infra — see the incident below for what redeploying it actually took.

### Problem 5 (a false alarm): the first handshake attempt didn't land in time

With DNS, TLS SAN, TLS trust, and the advertised endpoint all fixed, the join got
dramatically further on the very first retry after boot:

```
siderolink connection configured {"endpoint": "https://omni-siderolink.test:8443?jointoken=...",
  "node_uuid": "...", "node_address": "fdae:...:.../64"}
created new link {"link": "siderolink", "kind": "wireguard"}
assigned address {"address": "fdae:.../64", "link": "siderolink"}
reconfigured wireguard link {"link": "siderolink", "peers": 1}
```

And, in Omni's own server logs at the same moment:

```
"msg":"reference existing wireguard peer","public_key":"...","owner":"Links.omni.sidero.dev(default/<uuid>@7)"
"controller":"PendingMachineStatusController" ... reconcile succeeded
...30s later...
"msg":"cleaned up the pending machine link after grace period"
```

That first attempt's registration got torn down by Omni's own ~30s grace-period
timeout before the actual WireGuard handshake completed. Two rounds of packet
capture were used to chase this down:

1. **Inside the Docker container's own network namespace** (a sidecar joining
   `--network container:controlplane-1`, `tcpdump -i any udp port 30180`): zero
   packets from the VM's address (`10.6.0.2`) showed up in that specific capture
   window — only unrelated background noise (an external UDP prober at `8.8.8.8`
   triggering WireGuard's cookie-reply anti-amplification response).
2. **On the Mac's own `bridge100` interface** (`sudo tcpdump -i bridge100 udp port
   30180`, run by the user — raw interface capture needs root): real bidirectional
   traffic, `10.6.0.2 ↔ 10.6.0.1:30180`.

At the time this read as a hard wall — a theory that Docker Desktop's UDP
port-forwarding layer (`com.docker.backend`) wasn't transparently relaying the
handshake. **That theory was wrong.** The Talos client kept retrying automatically
after the first grace-period timeout, without any further intervention, and a later
attempt went all the way through: Omni's Machines page showed `Total: 1`, `Allocated:
1`, status `Installing`, and — conclusively — **live log streaming from the machine,
through the tunnel, into Omni's UI**, something only possible with a genuinely
working WireGuard data plane. It even got far enough that Omni auto-provisioned it
into a cluster (`talos-default`) and began pulling the Talos installer image from the
local image factory.

## Bonus: auto-provisioning hit a real, separate image-factory bug

Once registered, Omni auto-assigned the free machine to a cluster template
(`talos-default`) and started installing Talos onto it — pulling the installer image
from the local image factory rather than the public one. That pull failed:

```
error pushing index: Post "https://ghcr.io/v2/siderolabs/metal-installer/.../blobs/uploads/":
  ... DENIED: requested access to the resource is denied
```

The local factory correctly caches schematics and build artifacts to its own local
registry (`registry.image-factory.svc.cluster.local:5000`), but was still trying to
push the *final* installer image to the real upstream `ghcr.io/siderolabs` namespace
— which nothing self-hosted has credentials for. Root cause, found by cloning the
actual `image-factory` source (`v1.4.0`, matching the deployed chart) rather than
guessing from `values.yaml` comments: the push destination is
`options.Artifacts.Installer.Internal`, i.e. `artifacts.installer.internal` in
`config.yaml` — nested *inside* `artifacts`, alongside `schematic`, not a sibling of
it. A first fix attempt placed `installer:` as a sibling of `artifacts:` in
`kustomize/image-factory/install/image-factory/helm-release.yaml` — syntactically
valid, rendered into the ConfigMap looking plausible, but silently read as an
unrelated top-level key and never touched the running default. Corrected by nesting
it properly and explicitly clearing `namespace` (its own undocumented default is
`siderolabs`, which would otherwise survive since koanf only replaces keys a config
file actually sets, not ones it omits):

```yaml
config:
  artifacts:
    schematic:
      ...
    installer:
      internal:
        registry: ${factory_installer_registry}
        namespace: ""
        repository: ${factory_installer_repository:-installer}
        insecure: ${factory_installer_insecure:-false}
```

With the fix deployed and verified (`kubectl get cm image-factory` showing
`artifacts.installer.internal.registry` correctly set), the installer image push
succeeded and the machine proceeded past that step. This is a real facet bug,
independent of the SideroLink registration spike itself — same class of "looked right
in the rendered YAML, wrong per the actual upstream schema" mistake the fix itself
was trying to correct.

## Bonus: Omni's real "Download Installation Media" flow

Rather than hand-assembling `SideroLinkConfig`/`TrustedRootsConfig` documents, Omni's
own UI (Machines → Download Installation Media) generates a bootable ISO with the
join baked directly into kernel args:

```
customization:
    extraKernelArgs:
        - siderolink.api=https://omni-siderolink.test:8443?jointoken=...
        - talos.events.sink=[fdae:41e4:649b:9303::1]:8091
        - talos.logging.kernel=tcp://[fdae:41e4:649b:9303::1]:8092
```

built and served by the manager's own local image factory
(`factory.test:8443/image/<schematic>/...`), with the modern one-line equivalent
`talosctl cluster create qemu --schematic-id=... --talos-version=v1.13.5` also
surfaced right on the confirmation screen. Downloaded and booted a fresh VM from it —
this confirmed, independently, that the **DNS fix (Problem 1) is a real requirement**
regardless of approach: without `--nameservers 10.6.0.1`, the baked-in join failed
with `name resolver error: produced zero addresses`; with it, DNS resolved and the
join reached the expected next step, TLS trust (Problem 3) — same wall, same fix.

The wizard has an "Embedded machine configuration" field meant for exactly this
(pasting a `TrustedRootsConfig` doc to bake CA trust into the image itself, avoiding
a separate `apply-config` step entirely) — but it's a Monaco editor that would not
accept synthetic input from this session's browser automation (tried direct fill, CDP
key events, and `execCommand('insertText')`; all silently no-op). Not pursued further
since the manual `apply-config` approach already had full, verified proof — a human
filling that field in directly would work fine.

## Final conclusion

**This works.** Every layer — DNS, TLS hostname/SAN validation, CA trust, the
advertised WireGuard endpoint, Omni's server-side SideroLink peer registration, and
the WireGuard data plane itself through Docker Desktop's UDP NodePort publish — all
function correctly once configured right. The one apparent "wall" (Problem 5) turned
out to be an artifact of judging success from a single handshake attempt instead of
letting the client's normal retry loop run — a longer `sleep` before checking Omni's
Machines page would have shown the same result without any packet capture at all.

**Practical implication:** a container-based Talos "machine" cannot join Omni locally
(Attempt 1) — Omni's own UI is right to point at QEMU instead. A QEMU VM genuinely
can, on this exact local dev setup, once four things are true: `*.test` DNS resolves
to something the VM can actually reach (not `dns.test`'s host-loopback-only answer),
the join dials a hostname matching the gateway cert's SAN, the VM trusts this repo's
Private CA, and `omni.wireguard.advertised_endpoint` points at an address reachable
from wherever the test machine actually runs (not the Mac's bare loopback, unless the
test machine genuinely shares the Mac's own network namespace). None of this points
at a bug in `addon-omni.yaml` or the gateway's TLS setup — it's exactly the shape of
setup a real remote machine would need too, just satisfied here with local
workarounds instead of real DNS/PKI infrastructure.

**And it doesn't stop at registration.** With all of the above fixed plus the
image-factory bug below, a registered machine was assigned to a new cluster through
Omni's normal UI flow and, unassisted after that, finished a real bootstrap: etcd
formed, the Kubernetes API came up, and the cluster reached `Running` /
`Machines Healthy: 1/1`. Every layer of the stack this ADR describes — SideroLink,
the image factory, the gateway, the Private CA — works together correctly, not just
in isolation.

## Operational incident {#operational-incident}

Setting `omni.wireguard.advertised_endpoint` (Problem 4) meant editing
`contexts/local/values.yaml` and running `windsor up` to redeploy — not throwaway
spike infra. That triggered a real regression worth remembering:

- `windsor up` recreated `controlplane-1` (Terraform's normal behavior on a
  values.yaml change), which then failed to restart:
  `ports are not available: exposing port TCP 0.0.0.0:6443 -> ...: address already in use`.
  Root cause: the QEMU spike's own load balancer process
  (`talosctl-darwin-arm64 loadbalancer-launch --loadbalancer-addr 0.0.0.0
  --loadbalancer-ports 6443`) was squatting on host port 6443 — a genuine port
  collision between the spike's own infra and the real local cluster, not caused by
  the values.yaml edit itself. Destroying the spike VM (`talosctl cluster destroy`)
  freed the port and let the real cluster recover.
- The subsequent `windsor up` then hit a second, unrelated issue: Terraform's
  `talos_machine_bootstrap` resource fell out of state (its
  `replace_triggered_by` chain fired on the container recreate) and tried to
  re-bootstrap a node whose etcd data directory — on a bind-mounted, independently
  persisted disk — already existed: `rpc error: code = AlreadyExists desc = etcd
  data directory is not empty`. This resource type has no `terraform import`
  support (it models an RPC action, not real infrastructure), so there was no clean
  state fix available; the actual cluster was fully healthy throughout despite the
  Terraform error (`kubectl get nodes` showed `Ready`, Omni's pod `Running`). The
  user chose to recreate the local cluster from scratch rather than hand-edit
  Terraform state.
- A full recreate also **rotated the Private CA** (Problem 3) and **invalidated the
  previously-downloaded join token**, both of which needed re-fetching before the
  join could proceed again — both straightforward once identified, but easy to miss
  as separate failures if you don't expect a full recreate to touch them.

**Takeaway:** changing `omni.wireguard.advertised_endpoint` for a spike like this is
a real, deployed config change with real blast radius — not something to fold into a
throwaway test without expecting to interact with the actual local cluster's own
Terraform/Flux reconciliation, and without reverting it afterward. `10.6.0.1:30180`
is meaningless once the spike's ephemeral QEMU bridge is torn down; this value should
be reverted (and `windsor up` re-run) once the spike concludes, deliberately, not as
a side effect of moving on to something else.

A second, independent discovery from repeating this cycle several times while
verifying the image-factory fix above: **`windsor up` appears to unconditionally
recreate `controlplane-1` on every single invocation**, even for changes (like the
image-factory Kustomize fix) that touch nothing in the `compute` Terraform module's
own inputs. The cluster always self-heals from the container's persisted disk
regardless, but Terraform's own `talos_machine_bootstrap` bookkeeping hits the exact
same "etcd data directory is not empty" wall described above *every time* — the only
clean recovery found was a full `windsor down && windsor up`, not a plain `windsor
up` retry. This is a real, separate finding worth investigating on its own; not
pursued further here beyond documenting the reproduction.

## Useful commands discovered along the way

- `omnictl jointoken omni-endpoint` / `machine-config` / `kernel-args` — generate join
  material from the CLI, once `omnictl` has an authenticated `omniconfig`.
- Omni's home page ("General Information" panel) surfaces the SideroLink API
  endpoint, WireGuard endpoint, and a masked join token directly.
- `~/.talos/clusters/<name>/state.yaml`, `ipam.db`, `lb.log`, and
  `<name>-<node>.log` are all plain files — a QEMU cluster's node IPs, load-balancer
  activity, and console output are all readable without root even though creating
  the cluster needs it.
- `windsor exec -- kubectl ...` reaches the real cluster directly, sidestepping any
  broken/stale `kubectl` contexts (e.g. an OIDC context that assumes port 443 rather
  than this environment's `:8443`).
- A sidecar container (`--network container:<name>`) is a clean, no-sudo way to
  inspect another container's network namespace — used here for `tcpdump` inside
  `controlplane-1` without touching the host.
