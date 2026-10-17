#!/usr/bin/env bash
# One-time Incus cluster bootstrap -- the parts Nix can't declare
# (modules/cluster/incus.nix has the rest). Run after cluster-ceph-bootstrap.sh:
#
#   ./cluster-incus-bootstrap.sh
#
# 1. init the first node as a cluster, join the others with one-time tokens
# 2. "remote" storage pool on the Ceph `vms` pool
# 3. incusbr0 NAT bridge (per member) and the default profile
# 4. cluster.healing_threshold
#
# Safe to re-run: each step skips whatever already exists.
set -euo pipefail
cd "$(dirname "$0")"
source ./cluster-nodes.sh

FIRST=${NODES[0]}
# Seconds a member stays offline before its instances are restarted
# elsewhere. 60 for the test lab; the real value waits on measured
# Thunderbolt reconvergence (see the design doc's open questions).
HEALING_THRESHOLD=${HEALING_THRESHOLD:-60}

# exclusive-lock is what fences a partitioned node: the member that heals
# an instance breaks the lock, which blocklists the old node's RBD client,
# so its stale copy can't write. Incus' default is "layering" only, and
# without exclusive-lock a healed instance and its stale copy both write
# the same disk (seen in testing: real filesystem corruption).
RBD_FEATURES=layering,exclusive-lock,object-map,fast-diff,deep-flatten

mesh() { echo "fd9a:7af:74af:ff::$1"; }

echo "== preflight"
for n in "${NODES[@]}"; do
  on "$n" "systemctl is-active --quiet incus" || { echo "$(name "$n"): incus not running" >&2; exit 1; }
done
on "$FIRST" "ceph health | grep -q HEALTH_OK" || { echo "ceph is not HEALTH_OK" >&2; exit 1; }
echo "== tailscale"
require_tailscale
# Every step below skips what already exists, so a run that stopped halfway
# can simply be re-run.
members_now=$(on "$FIRST" "incus cluster list -f csv -c n 2>/dev/null" </dev/null || true)

if [ -z "$members_now" ]; then
  echo "== init $(name "$FIRST")"
  on "$FIRST" "incus admin init --preseed" <<EOF
config:
  core.https_address: "[$(mesh 1)]:8443"
  cluster.https_address: "[$(mesh 1)]:8443"
cluster:
  server_name: $(name "$FIRST")
  enabled: true
EOF
else
  echo "== $(name "$FIRST") already clustered"
fi

i=1
for n in "${NODES[@]:1}"; do
  i=$((i + 1))
  if grep -qx "$(name "$n")" <<<"$members_now"; then
    echo "== $(name "$n") already a member"; continue
  fi
  echo "== join $(name "$n")"
  token=$(on "$FIRST" "incus cluster add $(name "$n") -q" </dev/null)
  on "$n" "incus admin init --preseed" <<EOF
cluster:
  enabled: true
  server_name: $(name "$n")
  server_address: "[$(mesh $i)]:8443"
  cluster_token: "$token"
EOF
done

echo "== storage, network, profile"
members=""
for n in "${NODES[@]}"; do members+=" $(name "$n")"; done
# This script reaches the node on stdin, so every incus command gets
# </dev/null -- otherwise `incus ... create` reads the rest of the script as
# YAML config.
on "$FIRST" bash -euo pipefail -s <<EOF
state() { incus \$1 list -f csv -c ns </dev/null | awk -F, -v n="\$2" '\$1==n {print \$2}'; }

# Ceph pools need the per-member step first: "source" is member-specific.
if [ "\$(state storage remote)" != CREATED ]; then
  for m in $members; do incus storage create remote ceph source=vms --target \$m </dev/null >/dev/null 2>&1 || true; done
  incus storage create remote ceph ceph.user.name=admin ceph.rbd.features=$RBD_FEATURES </dev/null
else echo "storage pool remote exists"; fi

if [ "\$(state network incusbr0)" != CREATED ]; then
  for m in $members; do incus network create incusbr0 --target \$m </dev/null >/dev/null 2>&1 || true; done
  incus network create incusbr0 ipv4.address=10.200.0.1/24 ipv4.nat=true ipv6.address=none </dev/null
else echo "network incusbr0 exists"; fi

devices=\$(incus profile device list default </dev/null)
grep -qx root <<<"\$devices" || incus profile device add default root disk path=/ pool=remote </dev/null
grep -qx eth0 <<<"\$devices" || incus profile device add default eth0 nic network=incusbr0 name=eth0 </dev/null
# Cold-migrate (stop, move, start) on evacuation -- no live-migration, no
# CPU-model matching between hosts.
incus profile set default cluster.evacuate=migrate </dev/null

incus config set cluster.healing_threshold=$HEALING_THRESHOLD </dev/null

incus cluster list </dev/null
incus storage show remote </dev/null
incus profile show default </dev/null
EOF
