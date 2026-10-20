# Shared by the cluster's workstation apps (nix run .#cluster-<name>, one
# file each in this directory): which nodes, and how to reach them. Spliced
# into every app's script, so each one is a single self-contained program.
# (The leading underscore keeps import-tree from loading this as a module.)
#
#   mkApp { name; runtimeInputs; text; }  ->  a writeShellApplication with
#                                             the library in front of `text`
{ pkgs, lib }: let
  hosts = import ../_hosts.nix;
  # Node-id order (mesh address fd9a:7af:74af:ff::<id>), not name order: the
  # scripts number the mesh addresses by position in NODES.
  names = lib.sort (a: b: hosts.${a}.id < hosts.${b}.id) (lib.attrNames hosts);

  # Host keys are pre-seeded and fixed (_hosts.nix), so SSH checks them
  # strictly: a node presenting any other key is refused. Port 22 (root, test
  # lab) and 20530 (shot, e.g. as a tunnel's jump host).
  knownHosts = pkgs.writeText "cluster-known-hosts" (lib.concatMapStrings (n: let
    h = hosts.${n};
    key = lib.concatStringsSep " " (lib.take 2 (lib.splitString " " h.hostKey));
  in "${h.sshAddr} ${key}\n[${h.sshAddr}]:20530 ${key}\n") names);

  libText = /* bash */ ''
    # Run from the nix-config checkout: the apps build from the flake (.#...)
    # and read files in it (secrets/, modules/cluster/_lan.nix).
    [ -f flake.nix ] && [ -d modules/cluster ] \
      || { echo "run this from the nix-config checkout: nix run .#<app>" >&2; exit 1; }

    NODES=(${lib.concatMapStringsSep " " (n: "${n}=${hosts.${n}.sshAddr}") names})
    KEY=''${KEY:-$HOME/.ssh/nixos}

    name() { echo "''${1%%=*}"; }
    ip()   { echo "''${1#*=}"; }

    _TMP=$(mktemp -d -t cluster.XXXX)
    trap '_cleanup' EXIT
    KNOWN_HOSTS=${knownHosts}

    SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o "UserKnownHostsFile=$KNOWN_HOSTS"
              -o StrictHostKeyChecking=yes -o LogLevel=ERROR)
    # shellcheck disable=SC2029  # the command is meant to expand here, then run there
    on()   { local target=$1; shift; ssh "''${SSH_OPTS[@]}" "root@$(ip "$target")" "$@"; }

    # ---- Reaching a node that's booted into an installer ----------------------
    # The generic test-lab ISO answers on the management address. So does a
    # node's rescue installer (installer.nix) when the LAN has DHCP; it always
    # answers on its mesh address too, reached through a tunnel: a local port
    # forwarded over a healthy node (as shot, port 20530) to <mesh>:22 -- what
    # node.nix's PermitOpen allows. installer_find tries the LAN first.
    # Installers make a new host key each boot, so theirs isn't checked
    # (throwaway known_hosts).
    INST_SSH=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o "UserKnownHostsFile=$_TMP/installer_known_hosts"
              -o StrictHostKeyChecking=no -o LogLevel=ERROR)
    declare -A INST_HOST INST_PORT

    # installer_find <name=ip>: is it on an installer, and where? Sets
    # INST_HOST/INST_PORT for it (opening a tunnel if needed); fails if not found.
    installer_find() {
      local n=$1 nm id=0 i=0 e other port sock
      nm=$(name "$n")
      if ssh "''${INST_SSH[@]}" "root@$(ip "$n")" 'test -d /iso' 2>/dev/null; then
        INST_HOST[$nm]=$(ip "$n"); INST_PORT[$nm]=22; return 0
      fi
      for e in "''${NODES[@]}"; do i=$((i + 1)); [ "$e" = "$n" ] && id=$i; done
      for other in "''${NODES[@]}"; do
        [ "$other" = "$n" ] && continue
        # A random local port: a fixed one collided when cluster-rebuild and
        # the cluster-testlab it runs each opened a tunnel to the same node.
        port=$((30000 + RANDOM % 20000))
        sock=$_TMP/tunnel-$nm
        ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o "UserKnownHostsFile=$KNOWN_HOSTS" \
            -o StrictHostKeyChecking=yes -o LogLevel=ERROR -o ExitOnForwardFailure=yes \
            -f -N -M -S "$sock" -L "$port:[fd9a:7af:74af:ff::$id]:22" -p 20530 "shot@$(ip "$other")" 2>/dev/null || continue
        if ssh "''${INST_SSH[@]}" -p "$port" root@127.0.0.1 'test -d /iso' 2>/dev/null; then
          INST_HOST[$nm]=127.0.0.1; INST_PORT[$nm]=$port; return 0
        fi
        ssh -S "$sock" -O exit x 2>/dev/null || true
      done
      return 1
    }
    # inst <name=ip> <command>: run a command on that node's installer (as root).
    inst() { local nm; nm=$(name "$1"); shift; ssh "''${INST_SSH[@]}" -p "''${INST_PORT[$nm]}" "root@''${INST_HOST[$nm]}" "$@"; }

    _cleanup() {
      local s
      for s in "$_TMP"/tunnel-*; do [ -S "$s" ] && ssh -S "$s" -O exit x 2>/dev/null; done
      rm -rf "$_TMP"
    }

    # What the nodes need from each other before any bootstrap: every node can
    # reach every other one as shot over SSH on the mesh -- what the `cluster`
    # tool runs on (`cluster check-ssh`, modules/cluster/tools.nix). Tailscale
    # is only for your own remote access, so it's reported but never blocks
    # (the cluster has to come up without internet too).
    require_access() {
      local n bad=0 state out
      for n in "''${NODES[@]}"; do
        out=$(on "$n" 'runuser -u shot -- cluster check-ssh' 2>&1) || bad=1
        # shellcheck disable=SC2001  # indent every line of a multi-line answer
        sed 's/^/  /' <<<"$out"
      done
      if [ "$bad" != 0 ]; then
        cat >&2 <<'EOF'

    Mesh SSH between the nodes isn't working. Check that mesh-online is active
    on every node, /run/agenix/cluster-ssh-key exists (decrypted with the
    node's host key), and every node runs the current config. Then re-run.
    EOF
        return 1
      fi
      for n in "''${NODES[@]}"; do
        state=$(on "$n" "tailscale status --self --peers=false --json | jq -r '[.BackendState, ((.Self.Tags // []) | index(\"tag:cluster\") != null)] | @tsv'" 2>/dev/null || echo "unreachable")
        case $state in
          $'Running\ttrue') echo "  $(name "$n"): Tailscale logged in, tag:cluster" ;;
          $'Running\tfalse') echo "  $(name "$n"): WARN Tailscale logged in but NOT tagged tag:cluster" ;;
          *) echo "  $(name "$n"): WARN not on Tailscale ($state) -- remote access only, not needed by the cluster" ;;
        esac
      done
    }

  '';
in {
  inherit hosts names;
  mkApp = { name, runtimeInputs ? [ ], text }: pkgs.writeShellApplication {
    inherit name;
    # Not every app calls every shared helper.
    excludeShellChecks = [ "SC2329" ];
    runtimeInputs = [ pkgs.openssh pkgs.coreutils pkgs.gnused pkgs.gawk pkgs.gnugrep ] ++ runtimeInputs;
    text = libText + text;
  };
}
