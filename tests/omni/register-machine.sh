#!/usr/bin/env bash
#
# register-machine.sh - Boot a local QEMU Talos VM and register it with the local Omni
# instance over SideroLink, proving addon-omni.yaml's SideroLink path works end to end.
#
# Background: docs/spikes/omni-docker-machine-registration.md has the full story of why
# this exists in this shape. In short: a Docker container can't complete a SideroLink
# join at all (Talos's PLATFORM=container mode never brings up the WireGuard client), so
# this drives talosctl's QEMU provisioner instead - which needs root for CNI bridge
# networking and Hypervisor.framework acceleration, and needs a few workarounds to reach
# a local Omni running behind Docker Desktop.
#
# Usage:
#   task test:omni -- --join-config ~/Downloads/machine-config.yaml
#   tests/omni/register-machine.sh --join-config ~/Downloads/machine-config.yaml
#   tests/omni/register-machine.sh --clean
#
# Prerequisites:
#   - macOS with Docker Desktop, and `windsor up` already converged against the "local"
#     context (this drives docker-desktop-specific reachability workarounds; see the
#     spike doc for what a Linux/CI variant would need instead).
#   - A machine join config downloaded from Omni's own UI: sign in, then Home ->
#     "Download Machine Join Config". This is the one manual step - Omni's join tokens
#     aren't reachable headlessly without a pre-configured omnictl service account, and
#     setting one up isn't worth it for a local spike script. Defaults to
#     ~/Downloads/machine-config.yaml if present and --join-config is omitted.
#   - sudo access - talosctl's QEMU provisioner needs root for CNI bridge networking and
#     Hypervisor.framework acceleration. You'll be prompted once per VM (re)create.
#
# What it does:
#   1. Fetches this cluster's self-signed Private CA directly from Kubernetes (no
#      manual step - the gateway's cert is issued by it, and a bare VM needs to be told
#      to trust it explicitly).
#   2. Appends a TrustedRootsConfig document to the downloaded join config so the CA
#      trust rides along with the SideroLink join in a single config push (a Talos
#      maintenance-mode boot only accepts one).
#   3. Stands up a small additive DNS responder bound to the QEMU bridge's own gateway
#      address, answering *.test with that address instead of the loopback Windsor's own
#      dns.test hardcodes (which only makes sense for the Mac itself) - with a real
#      upstream forward for everything else, since the VM's own Kubernetes bootstrap
#      needs to resolve registry.k8s.io too.
#   4. Boots a QEMU VM from a plain Talos ISO in maintenance mode and pushes the
#      assembled config to it.
#
# Flags:
#   --join-config PATH    path to Omni's downloaded machine-config.yaml
#                          (default: ~/Downloads/machine-config.yaml if it exists)
#   --name NAME            talosctl cluster name (default: omni-siderolink-test)
#   --cidr CIDR            /24 CIDR for the QEMU bridge network (default: 10.6.0.0/24 -
#                          chosen to avoid colliding with windsor-local's 10.5.0.0/16)
#   --talos-version VER    Talos version to boot (default: matches the installed
#                          talosctl client)
#   --clean                tear down a previous run's VM and DNS override, then exit
#                          (the VM is left running after a normal registration run, since
#                          it needs to stay up to remain registered - run this when done)
#   -h, --help              show this help
#
# After it registers, the machine shows up as a free machine in Omni's UI (Machines
# page) or "Recent Machines" on the home page. From there, assigning it to a cluster and
# watching it install is a normal Omni UI flow, not something this script drives.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

NAME="omni-siderolink-test"
CIDR="10.6.0.0/24"
TALOS_VERSION=""
JOIN_CONFIG="${HOME}/Downloads/machine-config.yaml"
JOIN_CONFIG_EXPLICIT=0
CLEAN_ONLY=0

print_usage() {
  awk '/^#!/{next} /^# ?/{sub(/^# ?/,""); print; next} /^set -euo/{exit}' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --join-config)
      JOIN_CONFIG="$2"
      JOIN_CONFIG_EXPLICIT=1
      shift 2
      ;;
    --name) NAME="$2"; shift 2 ;;
    --cidr) CIDR="$2"; shift 2 ;;
    --talos-version) TALOS_VERSION="$2"; shift 2 ;;
    --clean) CLEAN_ONLY=1; shift ;;
    -h | --help)
      print_usage
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

case "$(uname -s)" in
  Darwin) ;;
  *)
    echo "error: this script drives talosctl's QEMU provisioner on macOS (Hypervisor.framework)." >&2
    echo "  see docs/spikes/omni-docker-machine-registration.md for the Linux/CI story." >&2
    exit 1
    ;;
esac

# Network prefix (first three octets) of the CIDR, e.g. "10.6.0" from "10.6.0.0/24".
# Only correct for /24s - matches this script's own single default and every flag value
# it's reasonable to pass.
NETWORK="${CIDR%%/*}"
NET_PREFIX="${NETWORK%.*}"
GATEWAY="${NET_PREFIX}.1"
VM_IP="${NET_PREFIX}.2"
DNS_CONTAINER="${NAME}-dns"

ARCH=$(uname -m)
case "$ARCH" in
  arm64) ;;
  x86_64) ARCH=amd64 ;;
esac

CLIENT_VERSION=$(talosctl version --client 2>/dev/null | awk '/Tag:/{print $2}')
TALOS_VERSION="${TALOS_VERSION:-${CLIENT_VERSION#v}}"

# aqua's talosctl is a version-dispatching proxy; under sudo its internal lookup of
# the real binary can land on a stale one via secure_path. Resolve to the real
# pinned binary directly to avoid that.
if command -v aqua >/dev/null 2>&1 && aqua which talosctl >/dev/null 2>&1; then
  TALOSCTL=$(aqua which talosctl)
else
  TALOSCTL=$(command -v talosctl)
fi

sudo_talosctl() {
  sudo -E "$TALOSCTL" "$@"
}

cleanup_all() {
  echo "==> destroying ${NAME}"
  sudo_talosctl cluster destroy --name "$NAME" >/dev/null || true
  docker rm -f "$DNS_CONTAINER" >/dev/null 2>&1 || true
}

if [ "$CLEAN_ONLY" = 1 ]; then
  cleanup_all
  exit 0
fi

if [ ! -f "$JOIN_CONFIG" ]; then
  if [ "$JOIN_CONFIG_EXPLICIT" = 1 ]; then
    echo "error: ${JOIN_CONFIG} not found" >&2
  else
    echo "error: no --join-config given and ${JOIN_CONFIG} does not exist." >&2
    echo "  sign in to Omni and use Home -> \"Download Machine Join Config\", then pass" >&2
    echo "  its path with --join-config (or leave it at the default Downloads location)." >&2
  fi
  exit 1
fi

# --- fetch/cache a Talos ISO -------------------------------------------------------------
ISO_CACHE="${HOME}/.talos/cache"
mkdir -p "$ISO_CACHE"
EMPTY_SCHEMATIC="376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
ISO_URL="https://factory.talos.dev/image/${EMPTY_SCHEMATIC}/v${TALOS_VERSION}/metal-${ARCH}.iso"
ISO_PATH="${ISO_CACHE}/$(echo "$ISO_URL" | tr '/:' '--')"
if [ ! -f "$ISO_PATH" ]; then
  echo "==> downloading Talos v${TALOS_VERSION} ${ARCH} ISO"
  curl -fSL -o "$ISO_PATH" "$ISO_URL"
fi

# --- fetch the cluster's Private CA -------------------------------------------------------
echo "==> fetching the cluster's Private CA"
CA_PEM=$(windsor exec -- kubectl get secret -n system-pki-trust private-ca-trust-cert \
  -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d)
if [ -z "$CA_PEM" ]; then
  echo "error: could not read the private-ca-trust-cert secret - is 'windsor up' converged?" >&2
  exit 1
fi

# --- assemble the final join config -------------------------------------------------------
# Canonicalized (cd + pwd -P) rather than the raw mktemp path: macOS's /var/folders/... is
# a symlink to /private/var/folders/..., and Docker Desktop's VirtioFS file sharing doesn't
# always resolve that symlink for bind mounts - it silently mounts an empty directory in
# place of the actual file instead of erroring, which the DNS override below needs to
# avoid hitting.
WORKDIR=$(mktemp -d)
WORKDIR=$(cd "$WORKDIR" && pwd -P)
trap 'rm -rf "$WORKDIR"' EXIT
FINAL_CONFIG="${WORKDIR}/join-config.yaml"
cp "$JOIN_CONFIG" "$FINAL_CONFIG"
{
  echo "---"
  echo "apiVersion: v1alpha1"
  echo "kind: TrustedRootsConfig"
  echo "name: private-ca"
  echo "certificates: |"
  echo "  ${CA_PEM//$'\n'/$'\n  '}"
} >>"$FINAL_CONFIG"

# --- boot the VM -----------------------------------------------------------------------------
echo "==> destroying any previous ${NAME} VM"
sudo_talosctl cluster destroy --name "$NAME" >/dev/null || true

echo "==> booting a QEMU Talos VM (sudo required: CNI bridge + Hypervisor.framework)"
# talosctl always writes controlplane.yaml/worker.yaml/talosconfig to its current working
# directory as part of PKI/secrets generation, regardless of --skip-injecting-config (that
# flag only skips applying the generated config to the VM, not generating the files) - run
# from WORKDIR so they don't land in the repo root.
(cd "$WORKDIR" && sudo_talosctl cluster create \
  --provisioner qemu \
  --name "$NAME" \
  --controlplanes 1 --workers 0 \
  --cidr "$CIDR" \
  --nameservers "$GATEWAY" \
  --iso-path "$ISO_PATH" \
  --skip-injecting-config \
  --wait=false)

# --- stand up the local DNS override -------------------------------------------------------
# Only possible now - the bridge interface (and GATEWAY's address on it) doesn't exist
# until talosctl's qemu provisioner creates it above.
echo "==> starting a local DNS override on ${GATEWAY}:53"
docker rm -f "$DNS_CONTAINER" >/dev/null 2>&1 || true
COREFILE_DIR="${WORKDIR}/corefile"
mkdir -p "$COREFILE_DIR"
cat >"${COREFILE_DIR}/Corefile" <<EOF
test:53 {
    template IN A {
        match "^.*\.test\.\$"
        answer "{{ .Name }} 60 IN A ${GATEWAY}"
    }
}
.:53 {
    forward . 1.1.1.1 8.8.8.8
}
EOF
docker run -d --name "$DNS_CONTAINER" \
  -p "${GATEWAY}:53:53/udp" \
  -v "${COREFILE_DIR}/Corefile:/etc/coredns/Corefile:ro" \
  coredns/coredns:latest -conf /etc/coredns/Corefile >/dev/null

echo "==> waiting for the VM's maintenance API"
ready=0
for _ in $(seq 1 30); do
  if "$TALOSCTL" get resolvers -n "$VM_IP" --insecure >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 3
done
if [ "$ready" = 0 ]; then
  echo "error: VM never became reachable at ${VM_IP}:50000" >&2
  exit 1
fi

echo "==> pushing the join config"
"$TALOSCTL" apply-config --insecure --nodes "$VM_IP" --file "$FINAL_CONFIG"

# The WireGuard handshake and Omni's own peer registration happen asynchronously after
# the config push - the VM has to stay up for this, not get torn down immediately after
# apply-config returns. Watching for the client-side confirmation line is enough to know
# it's worth checking Omni; it doesn't guarantee Omni's own side landed.
CONSOLE_LOG="${HOME}/.talos/clusters/${NAME}/${NAME}-controlplane-1.log"
echo "==> waiting for the SideroLink handshake"
joined=0
for _ in $(seq 1 20); do
  if grep -q "reconfigured wireguard link" "$CONSOLE_LOG" 2>/dev/null; then
    joined=1
    break
  fi
  sleep 3
done

cat <<EOF

$([ "$joined" = 1 ] && echo "SideroLink link established." || echo "No confirmation yet in the console log - it may still be retrying (this is normal on the first attempt; see docs/spikes/omni-docker-machine-registration.md, Problem 5).")
Check Omni's Machines page (or Home -> Recent Machines) for "${NAME}-controlplane-1".

Console log:  ${CONSOLE_LOG}

The VM is left running so it stays registered. Tear it down when you're done with:
  tests/omni/register-machine.sh --name ${NAME} --clean
EOF
