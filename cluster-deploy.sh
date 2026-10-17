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
EOF
}

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then for n in "${NODES[@]}"; do targets+=("$(name "$n")"); done; fi

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
    on "$n" 'systemctl reboot' || true
    timeout 600 bash -c "until b=\$(ssh ${SSH_OPTS[*]} root@$(ip "$n") cat /proc/sys/kernel/random/boot_id 2>/dev/null) && [ -n \"\$b\" ] && [ \"\$b\" != $boot ]; do sleep 5; done" \
      || { echo "$t didn't come back from the reboot within 10 min -- check its console" >&2; exit 1; }
  fi
  echo "== $t: waiting for it to be healthy"
  healthy "$n" || { echo "$t didn't come back healthy -- stopping here" >&2; exit 1; }
  echo "== $t: done"
done
