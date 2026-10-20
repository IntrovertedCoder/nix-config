#!/usr/bin/env bash
# Deploy the local working tree to cluster nodes, ONE AT A TIME, waiting for
# each to be healthy before the next -- Ceph and Incus quorum tolerate
# exactly one node down. Nothing is pushed or committed.
#
#   ./cluster-deploy.sh                    every node, in order
#   ./cluster-deploy.sh test-node2         just one
#   ACTION=boot ./cluster-deploy.sh        install as next boot and reboot
#                                          (kernel changes); default: switch
#
# `git add` new files first -- flakes only see tracked files.
set -euo pipefail
cd "$(dirname "$0")"
source ./cluster-nodes.sh

ACTION=${ACTION:-switch}
export NIX_SSHOPTS="${SSH_OPTS[*]}"

healthy() {  # healthy <node>: mesh up, and Ceph OK once it's bootstrapped
  on "$1" bash -s <<'EOF'
timeout 300 bash -c 'until [ "$(systemctl is-active mesh-online)" = active ]; do sleep 3; done' \
  || { echo "    mesh-online not active"; exit 1; }
if [ -e /etc/ceph/ceph.client.admin.keyring ] && [ -s /etc/ceph/ceph.client.admin.keyring ]; then
  timeout 900 bash -c 'until ceph health 2>/dev/null | grep -q HEALTH_OK; do sleep 10; done' \
    || { echo "    ceph not HEALTH_OK after 15 min:"; ceph health detail; exit 1; }
fi
failed=$(systemctl --failed --no-legend --plain | cut -d" " -f1)
[ -z "$failed" ] || { echo "    failed units: $failed"; exit 1; }
# Ceph can be HEALTH_OK while the node is still rejoining Incus (seen in
# testing), so also wait until no Incus member is offline.
if incus cluster list >/dev/null 2>&1 </dev/null; then
  timeout 300 bash -c 'until ! incus cluster list -f csv -c s </dev/null | grep -qx OFFLINE; do sleep 3; done' \
    || { echo "    incus members still offline after 5 min:"; incus cluster list </dev/null; exit 1; }
  # ...and until healing is re-armed (incus.nix, 2 min after the cluster is
  # whole). Otherwise a still-pending re-arm on some node can undo the
  # healing switch-off below right before a reboot (seen in testing).
  timeout 900 bash -c 'until systemctl is-active --quiet incus-healing-arm; do sleep 5; done' \
    || { echo "    incus-healing-arm hasn't finished after 15 min"; exit 1; }
fi
EOF
}

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  for n in "${NODES[@]}"; do targets+=("$(name "$n")"); done
  # Deploy the master router's node last: a router change restarts all
  # three routers in turn regardless of order, so whichever node goes last
  # is the one still holding the gateway when the others come back up --
  # one WAN blip (the last restart) instead of two or three (every backup
  # taking over, then handing back). Best-effort: if we can't tell who's
  # master, deploy in the default order.
  master=$(on "${NODES[0]}" "runuser -u shot -- cluster debug 2>&1" </dev/null \
    | sed -n 's/^\$ gateway .* is held by the router on: //p' | head -1) || true
  # "nobody (no router answering)" or an unknown MAC matches no node: no change.
  for i in "${!targets[@]}"; do
    if [ "${targets[$i]}" = "$master" ]; then
      unset 'targets[i]'
      targets=("${targets[@]}" "$master")
      echo "== master router is on $master -- deploying it last"
      break
    fi
  done
fi

for t in "${targets[@]}"; do
  n=""; for e in "${NODES[@]}"; do [ "$(name "$e")" = "$t" ] && n=$e; done
  [ -n "$n" ] || { echo "unknown node $t" >&2; exit 1; }
  echo "== $t: checking the cluster is healthy before touching it"
  for e in "${NODES[@]}"; do healthy "$e" || { echo "$(name "$e") isn't healthy -- not deploying" >&2; exit 1; }; done

  echo "== $t: nixos-rebuild $ACTION"
  nix run nixpkgs#nixos-rebuild -- "$ACTION" --flake ".#$t" --target-host "root@$(ip "$n")"
  if [ "$ACTION" = boot ]; then
    echo "== $t: rebooting"
    # Wait for a *new* boot id: sshd can still answer while shutdown is only
    # starting, which would look like "already back".
    boot=$(on "$n" 'cat /proc/sys/kernel/random/boot_id')
    # A planned reboot isn't a failure: switch healing off so a slow POST
    # can't move this node's instances away. incus-healing-arm (incus.nix)
    # on the rebooted node turns it back on once the cluster is whole again.
    on "$n" 'incus cluster list >/dev/null 2>&1 </dev/null && incus config set cluster.healing_threshold=0 </dev/null' || true
    on "$n" 'systemctl reboot' || true
    timeout 600 bash -c "until b=\$(ssh ${SSH_OPTS[*]} root@$(ip "$n") cat /proc/sys/kernel/random/boot_id 2>/dev/null) && [ -n \"\$b\" ] && [ \"\$b\" != $boot ]; do sleep 5; done" \
      || { echo "$t didn't come back from the reboot within 10 min -- check its console" >&2; exit 1; }
  fi
  echo "== $t: waiting for it to be healthy"
  healthy "$n" || { echo "$t didn't come back healthy -- stopping here" >&2; exit 1; }
  echo "== $t: done"
done
