#!/usr/bin/env bash
# Install cluster nodes from the LOCAL working tree -- nothing is pushed or
# committed. Each node must be booted into an installer: the test lab's
# generic ISO (reached on its management address), or the node's own rescue
# installer (modules/cluster/installer.nix, reached over the mesh through a
# healthy node). Installed nodes are refused, never kexec'd.
#
#   ./cluster-testlab.sh                 # all nodes, in parallel
#   ./cluster-testlab.sh test-node2      # just one
#
# Test lab, for a fresh start (on the Proxmox host):
#   ./testlab.sh rollback blank && ./testlab.sh start
#
# The system is built here and copied over SSH; the installer needs no
# internet. Only the boot disk is touched -- OSD disks are never wiped here
# (see modules/cluster/disko.nix). Flakes only see files git tracks: `git add`
# (stage, don't commit) any new file first.
set -euo pipefail
cd "$(dirname "$0")"
source ./cluster-nodes.sh

LOGS=$(mktemp -d -t testlab.XXXX)
AGE_IDENTITY=${AGE_IDENTITY:-$KEY}

targets=()
if [ $# -eq 0 ]; then
  for n in "${NODES[@]}"; do targets+=("$n"); done
else
  for want in "$@"; do
    found=""
    for n in "${NODES[@]}"; do [ "$(name "$n")" = "$want" ] && found=$n; done
    [ -n "$found" ] || { echo "unknown node $want" >&2; exit 1; }
    targets+=("$found")
  done
fi

for n in "${targets[@]}"; do
  if ! installer_find "$n"; then
    echo "$(name "$n") isn't booted into an installer (checked its management address" >&2
    echo "and its mesh address via the other nodes). Test lab, on the Proxmox host:" >&2
    echo "  ./testlab.sh rollback blank && ./testlab.sh start" >&2
    exit 1
  fi
  echo "$(name "$n"): installer found at ${INST_HOST[$(name "$n")]}:${INST_PORT[$(name "$n")]}"
done

for n in "${targets[@]}"; do
  nm=$(name "$n")

  # The node's pre-seeded SSH host key (secrets/hostkeys/<node>.age),
  # decrypted into a private temp dir that nixos-anywhere copies onto the
  # new root, where sshd.nix's preservation symlink points.
  dir=$_TMP/extra-$nm/persistent/etc/ssh
  install -d -m 0755 "$dir"
  ( umask 077; nix shell nixpkgs#age -c age -d -i "$AGE_IDENTITY" \
      "secrets/hostkeys/$nm.age" >"$dir/ssh_host_ed25519_key" )
  ssh-keygen -y -f "$dir/ssh_host_ed25519_key" >"$dir/ssh_host_ed25519_key.pub"

  # Clear the whole boot disk first. disko never reformats a partition that
  # already carries a filesystem signature, so after a damaged partition
  # table (or a reinstall over an old install) the old root filesystem
  # reappears inside the new partitions and gets reused -- seen in the
  # cluster-rebuild test. Only the boot disk, by its by-id path.
  boot=$(nix eval --raw ".#nixosConfigurations.$nm.config.var.cluster.host.bootDisk" 2>/dev/null)
  inst "$n" "umount -R /mnt 2>/dev/null; blkdiscard -f '$boot' 2>/dev/null || { for p in '$boot'-part*; do wipefs -a -f \"\$p\" 2>/dev/null; done; wipefs -a -f '$boot'; }" >/dev/null \
    || { echo "couldn't clear $nm's boot disk ($boot)" >&2; exit 1; }

  echo "installing $nm -> $LOGS/$nm.log"
  nix run nixpkgs#nixos-anywhere -- \
    --flake ".#$nm" -i "$KEY" \
    --extra-files "$_TMP/extra-$nm" \
    --no-substitute-on-destination \
    --target-host "root@${INST_HOST[$nm]}" -p "${INST_PORT[$nm]}" \
    --ssh-option "UserKnownHostsFile=$_TMP/installer_known_hosts" \
    --ssh-option StrictHostKeyChecking=no \
    >"$LOGS/$nm.log" 2>&1 &
done

fail=0
for job in $(jobs -p); do wait "$job" || fail=1; done
for n in "${targets[@]}"; do echo "== $(name "$n")"; tail -2 "$LOGS/$(name "$n").log"; done

if [ -e secrets/tailscale-cluster-oauth.age ]; then
  cat <<'EOF'

NEXT: check the nodes reach each other over mesh SSH before any bootstrap
script (they check too). Tailscale joins on its own a minute or two after
boot (OAuth secret in secrets/); it's only for remote access, so the check
just reports it:

  ./cluster-nodes.sh check-access
EOF
else
  cat <<'EOF'

NEXT: check the nodes reach each other over mesh SSH before any bootstrap
script (they check too):

  ./cluster-nodes.sh check-access

For remote access, log each node into Tailscale by hand (no OAuth secret
in secrets/ yet):

  sudo tailscale up --advertise-tags=tag:cluster

then open the printed URL. The tailnet ACL needs tag:cluster in tagOwners.
EOF
fi
exit $fail
