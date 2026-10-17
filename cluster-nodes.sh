#!/usr/bin/env bash
# Sourced by the cluster-*-bootstrap.sh scripts: which nodes, and how to
# reach them. name=ip, in node-id order (mesh address fd9a:7af:74af:ff::<id>).
#
# Run directly for the Tailscale check:  ./cluster-nodes.sh check-tailscale
NODES=(test-node1=10.123.58.148 test-node2=10.123.97.55 test-node3=10.123.135.218)
KEY=${KEY:-$HOME/.ssh/nixos}

name() { echo "${1%%=*}"; }
ip()   { echo "${1#*=}"; }

# Host keys are pre-seeded and fixed (modules/cluster/_hosts.nix), so SSH
# checks them strictly: a node presenting any other key is refused.
_TMP=$(mktemp -d -t cluster.XXXX)
trap '_cleanup' EXIT
KNOWN_HOSTS=$_TMP/known_hosts
_hostkeys=$(nix eval --raw --impure --expr '
  let h = import '"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'/modules/cluster/_hosts.nix;
  in builtins.concatStringsSep "\n" (map (n: n + " " + h.${n}.hostKey) (builtins.attrNames h))')
for _n in "${NODES[@]}"; do
  # port 22 (root, test lab) and 20530 (shot, e.g. as a tunnel's jump host)
  awk -v n="$(name "$_n")" -v ip="$(ip "$_n")" \
    '$1 == n { print ip, $2, $3; print "[" ip "]:20530", $2, $3 }' <<<"$_hostkeys" >>"$KNOWN_HOSTS"
done

SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o "UserKnownHostsFile=$KNOWN_HOSTS"
          -o StrictHostKeyChecking=yes -o LogLevel=ERROR)
on()   { local target=$1; shift; ssh "${SSH_OPTS[@]}" "root@$(ip "$target")" "$@"; }

# ---- Reaching a node that's booted into an installer ------------------------
# The generic test-lab ISO answers on the management address. A node's rescue
# installer (installer.nix) only answers on its mesh address, so it's reached
# through a tunnel: a local port forwarded over a healthy node (as shot, port
# 20530) to <mesh>:22 -- what node.nix's PermitOpen allows. Installers make a
# new host key each boot, so theirs isn't checked (throwaway known_hosts).
INST_SSH=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o "UserKnownHostsFile=$_TMP/installer_known_hosts"
          -o StrictHostKeyChecking=no -o LogLevel=ERROR)
declare -A INST_HOST INST_PORT

# installer_find <name=ip>: is it on an installer, and where? Sets
# INST_HOST/INST_PORT for it (opening a tunnel if needed); fails if not found.
installer_find() {
  local n=$1 nm id=0 i=0 e other port sock
  nm=$(name "$n")
  if ssh "${INST_SSH[@]}" "root@$(ip "$n")" 'test -d /iso' 2>/dev/null; then
    INST_HOST[$nm]=$(ip "$n"); INST_PORT[$nm]=22; return 0
  fi
  for e in "${NODES[@]}"; do i=$((i + 1)); [ "$e" = "$n" ] && id=$i; done
  for other in "${NODES[@]}"; do
    [ "$other" = "$n" ] && continue
    # A random local port: a fixed one collided when cluster-rebuild.sh and
    # the cluster-testlab.sh it runs each opened a tunnel to the same node.
    port=$((30000 + RANDOM % 20000))
    sock=$_TMP/tunnel-$nm
    ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o "UserKnownHostsFile=$KNOWN_HOSTS" \
        -o StrictHostKeyChecking=yes -o LogLevel=ERROR -o ExitOnForwardFailure=yes \
        -f -N -M -S "$sock" -L "$port:[fd9a:7af:74af:ff::$id]:22" -p 20530 "shot@$(ip "$other")" 2>/dev/null || continue
    if ssh "${INST_SSH[@]}" -p "$port" root@127.0.0.1 'test -d /iso' 2>/dev/null; then
      INST_HOST[$nm]=127.0.0.1; INST_PORT[$nm]=$port; return 0
    fi
    ssh -S "$sock" -O exit x 2>/dev/null || true
  done
  return 1
}
# inst <name=ip> <command>: run a command on that node's installer (as root).
inst() { local nm; nm=$(name "$1"); shift; ssh "${INST_SSH[@]}" -p "${INST_PORT[$nm]}" "root@${INST_HOST[$nm]}" "$@"; }

_cleanup() {
  local s
  for s in "$_TMP"/tunnel-*; do [ -S "$s" ] && ssh -S "$s" -O exit x 2>/dev/null; done
  rm -rf "$_TMP"
}

# Every node logged in, tagged tag:cluster, and able to reach every other
# node as shot over Tailscale SSH (which is what proves the tailnet ACL).
# The manual step after each install -- see modules/cluster/tailscale.nix.
require_tailscale() {
  local n m bad=0 state
  for n in "${NODES[@]}"; do
    state=$(on "$n" "tailscale status --self --peers=false --json | jq -r '[.BackendState, ((.Self.Tags // []) | index(\"tag:cluster\") != null)] | @tsv'" 2>/dev/null || echo "unreachable")
    case $state in
      $'Running\ttrue') echo "  $(name "$n"): logged in, tag:cluster" ;;
      $'Running\tfalse') echo "  $(name "$n"): logged in but NOT tagged tag:cluster"; bad=1 ;;
      *) echo "  $(name "$n"): not logged in ($state)"; bad=1 ;;
    esac
  done
  if [ $bad = 0 ]; then
    for n in "${NODES[@]}"; do for m in "${NODES[@]}"; do
      [ "$n" = "$m" ] && continue
      # By the peer's real hostname and online state, not its tailnet name
      # (which is "<node>-1" after a rebuild until renamed).
      if ! on "$n" "a=\$(tailscale status --json | jq -r --arg h $(name "$m") '[.Peer[]? | select(.HostName == \$h and .Online)] | first | .TailscaleIPs[0] // empty'); [ -n \"\$a\" ] && timeout 20 runuser -u shot -- tailscale ssh shot@\$a true </dev/null" >/dev/null 2>&1; then
        echo "  $(name "$n") -> $(name "$m"): Tailscale SSH as shot FAILED (check the tailnet ACL)"; bad=1
      fi
    done; done
    [ $bad = 0 ] && echo "  Tailscale SSH works between every pair of nodes"
  fi
  if [ $bad != 0 ]; then
    cat >&2 <<'EOF'

Tailscale isn't set up yet. On each node not marked OK above:

  sudo tailscale up --ssh --advertise-tags=tag:cluster

and make sure the tailnet ACL has the tag:cluster entries from
modules/cluster/tailscale.nix. Then re-run.
EOF
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case ${1:-} in
    check-tailscale) require_tailscale ;;
    *) echo "usage: $0 check-tailscale" >&2; exit 1 ;;
  esac
fi
