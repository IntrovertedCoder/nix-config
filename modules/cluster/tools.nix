{ lib, ... }: let
  hosts = import ./_hosts.nix;

  # `cluster` -- debug / restore / replace-osd, installed on every cluster
  # node. It only runs there; from a workstation:
  #   ssh -p 20530 shot@<node> cluster ...
  # (Bash `${...}` is written `''${...}` inside this Nix string.)
  #
  # Every command resolves to a pinned Nix store path, here and on the other
  # nodes: `tools` becomes the script's PATH, and on()/on_root() send the
  # same PATH along with each remote script, so nothing depends on a node's
  # login PATH. The CLIs come from the same packages the services run, so
  # e.g. the incus client always matches the daemon.
  mkCluster = { pkgs, config }: let
    tools = with pkgs; [
      coreutils gnugrep gawk gnused jq util-linux procps tailscale
      ceph                                       # ceph, rbd, ceph-volume
      config.virtualisation.incus.clientPackage  # incus
      frr                                        # vtysh
      config.services.chrony.package             # chronyc
      config.systemd.package                     # systemctl, journalctl
    ];
  in pkgs.writeShellApplication {
    name = "cluster";
    runtimeInputs = tools;
    text = ''
      CLUSTER_NODES=(${lib.concatStringsSep " " (lib.mapAttrsToList (name: h:
        "'${name}=${toString h.id}=${toString (builtins.length h.ring)}=${lib.concatStringsSep "," h.osdDisks}'"
      ) hosts)})
      TOOL_PATH=${lib.makeBinPath tools}

      # cluster -- day-to-day operations for the Elements cluster. Runs as shot on
      # any cluster node (from a workstation: ssh -p 20530 shot@<node> cluster ...):
      #
      #   cluster debug                                  health report to paste into a chat
      #   cluster restore <node>                         bring an evacuated node back, safely
      #   cluster replace-osd <node> <osd-id> <disk>     rebuild an OSD on a replacement disk
      #
      # Other nodes are reached over Tailscale SSH as shot (the tailnet ACL only
      # lets tag:cluster nodes do that); anything for this host runs locally.
      # Read-only Ceph access uses client.status (no root); the steps that change
      # Ceph or disks go through sudo and ask for shot's password.
      #
      # Set by tools.nix from modules/cluster/_hosts.nix:
      #   CLUSTER_NODES  "name=id=ringLinks=disk1,disk2" per node, in id order

      SELF=$(hostname)
      WAIT_SECS=''${CLUSTER_WAIT_SECS:-1800}

      die()  { printf 'cluster: %s\n' "$*" >&2; exit 1; }
      ok()   { printf '  ok    %s\n' "$*"; }
      info() { printf '  ..    %s\n' "$*"; }
      fail() { printf '  FAIL  %s\n' "$*" >&2; }

      field() {  # field <node> <1=id 2=ringLinks 3=disks>
        # All locals: bash scoping is dynamic, so a plain `read ... id` here would
        # overwrite a caller's own `id` (replace-osd's osd id, seen in testing).
        local e _f_id _f_ring _f_disks
        for e in "''${CLUSTER_NODES[@]}"; do
          if [ "''${e%%=*}" = "$1" ]; then
            IFS='=' read -r _ _f_id _f_ring _f_disks <<<"$e"
            case $2 in 1) echo "$_f_id" ;; 2) echo "$_f_ring" ;; 3) echo "$_f_disks" ;; esac
            return 0
          fi
        done
        return 1
      }
      node_names() { local e; for e in "''${CLUSTER_NODES[@]}"; do echo "''${e%%=*}"; done; }
      is_node()    { field "$1" 1 >/dev/null; }
      mesh_of()    { echo "fd9a:7af:74af:ff::$(field "$1" 1)"; }

      # on <node>: run the bash script on stdin there, as shot. (shot's login shell
      # is fish, so remote commands always go through `bash -s`.)
      # Every script starts by putting the pinned tools first on PATH.
      on() {
        if [ "$1" = "$SELF" ]; then { echo "export PATH=$TOOL_PATH:\$PATH"; cat; } | bash -s
        else
          local a; a=$(ts_addr "$1") || return 1
          { echo "export PATH=$TOOL_PATH:\$PATH"; cat; } | timeout 60 tailscale ssh "shot@$a" bash -s
        fi
      }
      # A node's Tailscale IP, found by its real hostname and online state --
      # not by its tailnet name: after a rebuild that name is "<node>-1" until
      # renamed in the admin console, and a stale offline entry can still hold
      # the plain name (plain-name lookup then fell through to a link-local
      # address in testing).
      ts_addr() {
        local a
        a=$(tailscale status --json 2>/dev/null | jq -r --arg n "$1" \
          '[.Peer[]? | select(.HostName == $n and .Online)] | first | .TailscaleIPs[0] // empty')
        [ -n "$a" ] || { echo "cluster: $1 isn't online in the tailnet" >&2; return 1; }
        echo "$a"
      }
      # on_root <node> <script>: run as root via sudo, interactively (password).
      # (sudo resets PATH, so the export goes inside the script.)
      on_root() {
        local b64
        # shellcheck disable=SC2016  # $PATH expands on the target, not here
        b64=$(printf 'export PATH=%s:$PATH\n%s\n' "$TOOL_PATH" "$2" | base64 -w0)
        if [ "$1" = "$SELF" ]; then printf '%s' "$b64" | base64 -d | sudo bash
        # -t goes after the host: `tailscale ssh` only takes [user@]host first,
        # and passes the rest to ssh (which accepts options after the host).
        else
          local a; a=$(ts_addr "$1") || return 1
          tailscale ssh "shot@$a" -t "echo $b64 | base64 -d | sudo bash"
        fi
      }
      reachable() { on "$1" <<<'true' >/dev/null 2>&1; }

      is_node "$SELF" || die "run this on a cluster node: ssh -p 20530 shot@<node> cluster ''${*:-debug}"

      # A node to ask cluster-wide questions: this one if its Incus answers (it
      # may be the broken one), else the first other node that does.
      CTRL=""
      control() {
        [ -n "$CTRL" ] && return 0
        local n
        for n in "$SELF" $(node_names); do
          if on "$n" <<<'incus cluster list >/dev/null' >/dev/null 2>&1; then CTRL=$n; return 0; fi
        done
        die "no cluster node answers (incus cluster list) -- run 'cluster debug' to see why"
      }
      ctl() { control; on "$CTRL"; }   # cluster-wide command on stdin

      # ------------------------------------------------------------------ debug
      # Summary lines for one node: hardware report verdict and attention list
      # (from cluster-hwcheck, see health.nix), its age, failed units, mesh.
      node_attention() {
        on "$1" <<'EOF' 2>/dev/null
      r=/run/cluster-health/report.txt
      if [ -r "$r" ]; then
        age=$(( ( $(date +%s) - $(stat -c %Y "$r") ) / 60 ))
        sed -n '/^ATTENTION:/,/^$/p' "$r" | tail -n +2 | grep -v '^  none$' | grep -v '^$' | sed 's/^  //'
        [ "$age" -gt 40 ] && echo "WARN  hardware report is ''${age} min old (is cluster-hwcheck.timer running?)"
      else
        echo "WARN  no hardware report yet (cluster-hwcheck runs 2 min after boot, then every 15 min)"
      fi
      for u in $(systemctl --failed --no-legend --plain | cut -d' ' -f1); do echo "FAIL  failed unit: $u"; done
      [ "$(systemctl is-active mesh-online)" = active ] || echo "FAIL  mesh-online is not active"
      true
      EOF
      }

      cmd_debug() {
        local n l lines any=0 summary
        echo "## Elements cluster debug report"
        echo
        echo "Generated $(date -u '+%F %T UTC') from $SELF."
        control

        # What needs attention, first -- the rest of the report is the evidence.
        echo
        echo "### Attention"
        echo '```'
        summary=$(ctl <<'EOF' 2>/dev/null
      h=$(ceph --id status health 2>&1)
      [ "''${h%% *}" = HEALTH_OK ] || echo "ceph: $h"
      crashes=$(ceph --id status crash ls-new 2>/dev/null | tail -n +2 | wc -l)
      [ "$crashes" -gt 0 ] && echo "ceph: $crashes recent daemon crashes not yet archived (ceph crash ls-new)"
      incus cluster list -f csv -c ns 2>/dev/null | awk -F, '$2 != "ONLINE" {print "incus: member " $1 " is " $2}'
      true
      EOF
      )
        if [ -n "$summary" ]; then echo "$summary"; any=1; fi
        for n in $(node_names); do
          if ! reachable "$n"; then echo "$n: FAIL  unreachable over Tailscale SSH"; any=1; continue; fi
          lines=$(node_attention "$n")
          if [ -n "$lines" ]; then
            while IFS= read -r l; do echo "$n: $l"; done <<<"$lines"
            any=1
          fi
        done
        [ $any = 0 ] && echo "nothing -- every check passed"
        echo '```'

        echo
        echo "### Cluster-wide (via $CTRL)"
        echo '```'
        ctl <<'EOF' 2>&1
      c() { echo "\$ $*"; "$@" 2>&1; echo; }
      c ceph --id status -s
      c ceph --id status health detail
      c ceph --id status osd tree
      c ceph --id status osd perf
      c ceph --id status df
      c ceph --id status osd pool ls detail
      c ceph --id status device ls
      c ceph --id status crash ls
      c ceph --id status osd blocklist ls
      c incus cluster list
      c incus list -c nsL4tS
      c incus storage info remote
      c incus config show
      EOF
        echo '```'
        for n in $(node_names); do
          echo
          echo "### $n"
          echo '```'
          if ! reachable "$n"; then echo "UNREACHABLE over Tailscale SSH"; echo '```'; continue; fi
          on "$n" <<'EOF' 2>&1
      c() { echo "\$ $*"; "$@" 2>&1; echo; }
      c uptime
      c systemctl is-active mesh-online frr ceph.target incus tailscaled chronyd
      c ip -br addr
      c vtysh -c "show openfabric neighbor"
      c vtysh -c "show ipv6 route openfabric"
      c vtysh -c "show openfabric topology"
      c journalctl -b -u mesh-online --no-pager -n 10 -o short-iso
      c chronyc tracking
      c chronyc sources
      c systemctl --failed --no-legend
      c rbd showmapped
      c journalctl -b -p warning --since -2h --no-pager -n 40 -o short-iso -u 'ceph*' -u incus -u frr -u mesh-online -u chronyd
      # healing/evacuation are logged at info level, so the filter above misses them
      c journalctl -u incus --no-pager -n 30 -o short-iso
      # unfiltered kernel errors (the hardware report hides e.g. RBD errors)
      c journalctl -k -b -p err --no-pager -n 30 -o short-iso
      echo "\$ cat /run/cluster-health/report.txt   # hardware, from cluster-hwcheck"
      cat /run/cluster-health/report.txt 2>&1
      EOF
          echo '```'
        done
      }

      # ------------------------------------------------------------------ restore
      ceph_wait_healthy() {  # ceph_wait_healthy [node-that-must-be-in-quorum]
        local start now status checks bad osds q total up inn
        start=$(date +%s)
        while :; do
          status=$(ctl <<<'ceph --id status health detail -f json')
          osds=$(ctl <<<'ceph --id status osd stat -f json' | jq -r '"\(.num_osds) \(.num_up_osds) \(.num_in_osds)"')
          q=$(ctl <<<'ceph --id status quorum_status -f json' | jq -r '.quorum_names | join(",")')
          read -r total up inn <<<"$osds"
          if [ "$(jq -r .status <<<"$status")" = HEALTH_OK ] && [ "$up" = "$total" ] && [ "$inn" = "$total" ] \
             && { [ -z "''${1:-}" ] || [[ ",$q," == *",$1,"* ]]; }; then
            ok "ceph HEALTH_OK, $up/$total OSDs up and in, quorum $q"
            return 0
          fi
          # Only "still catching up" warnings are worth waiting for.
          checks=$(jq -r '.checks | keys[]' <<<"$status")
          bad=$(grep -vxE 'PG_DEGRADED|PG_AVAILABILITY|OBJECT_MISPLACED|OSD_DOWN|OSD_HOST_DOWN|MON_DOWN|MON_CLOCK_SKEW|PG_NOT_DEEP_SCRUBBED|PG_NOT_SCRUBBED' <<<"$checks" || true)
          if [ -n "$bad" ]; then
            fail "ceph has problems that waiting won't fix: $(echo "$bad" | tr '\n' ' ')"
            ctl <<<'ceph --id status health detail' >&2
            return 1
          fi
          now=$(date +%s)
          if [ $((now - start)) -gt "$WAIT_SECS" ]; then
            fail "ceph still not healthy after ''${WAIT_SECS}s"; ctl <<<'ceph --id status -s' >&2; return 1
          fi
          info "waiting for ceph ($up/$total OSDs up, $inn in; $(echo "$checks" | tr '\n' ' '))"
          sleep 15
        done
      }

      cmd_restore() {
        local node=''${1:-} members st others origin stale ring ups failed inst bl lxcs qemus maps rebuilt
        [ -n "$node" ] || die "usage: cluster restore <node>"
        is_node "$node" || die "unknown node $node (known: $(node_names | tr '\n' ' '))"
        echo "== checks before restoring $node"

        # 1. right node, nothing else down
        members=$(ctl <<<'incus cluster list -f json')
        st=$(jq -r --arg n "$node" '.[] | select(.server_name==$n) | .status' <<<"$members")
        origin=$(ctl <<<'incus list -f json' | jq -r --arg n "$node" '.[] | select(.config["volatile.evacuate.origin"]==$n) | .name')
        # A rebuilt node (cluster-rebuild.sh) rejoins Incus as a new, Online
        # member, so its healed-away instances still name it as their origin
        # but `incus cluster restore` has nothing to restore. Move those back
        # by hand instead (step 8).
        if [ "$st" = Online ] && [ -n "$origin" ]; then
          rebuilt=1
        else
          rebuilt=0
          [ "$st" = Evacuated ] || die "$node is '$st', not Evacuated, and no instances were evacuated from it -- nothing to restore"
        fi
        others=$(jq -r --arg n "$node" '.[] | select(.server_name!=$n and .status!="Online") | "\(.server_name)=\(.status)"' <<<"$members")
        [ -z "$others" ] || die "other members aren't Online ($others) -- fix those first; the cluster has no spare"
        if [ $rebuilt = 1 ]; then
          ok "$node is Online (rebuilt) with instances still evacuated from it; every other member is Online"
        else
          ok "$node is Evacuated, every other member is Online"
        fi

        reachable "$node" || die "$node isn't reachable over Tailscale SSH"

        # 2. mesh
        ring=$(field "$node" 2)
        ups=$(on "$node" <<<'systemctl is-active mesh-online >/dev/null && vtysh -c "show openfabric neighbor" | grep -c " Up " || echo 0')
        [ "$ups" -ge "$ring" ] || die "$node mesh isn't up ($ups/$ring adjacencies; mesh-online must be active)"
        ok "mesh-online active, $ups/$ring OpenFabric neighbours Up"

        # 3+4. no stale instance copies: after a failure, Incus leaves the old
        # node's copies running (fenced, but alive) until it reboots.
        # shellcheck disable=SC2016  # expands on the remote node
        stale=$(on "$node" <<<'echo "$(pgrep -c -f "^\[lxc monitor\]" || true) $(pgrep -c qemu-system || true) $(rbd showmapped 2>/dev/null | tail -n +2 | wc -l)"')
        read -r lxcs qemus maps <<<"$stale"
        if [ "$lxcs" != 0 ] || [ "$qemus" != 0 ] || [ "$maps" != 0 ]; then
          die "$node still has instance processes or RBD mappings ($lxcs containers, $qemus VMs, $maps mapped) -- probably stale copies from before it failed. Reboot $node, then run this again."
        fi
        ok "no instance processes or RBD mappings left on $node"

        # 5. ceph caught up, node's mon back in quorum
        ceph_wait_healthy "$node" || die "ceph isn't ready"

        # 6. incus
        on "$node" <<<'systemctl is-active --quiet incus' || die "incus isn't running on $node"
        ctl <<<"incus info --target $node >/dev/null" || die "incus on $node doesn't answer"
        ok "incus active on $node and answering"

        # 7. healthy node
        failed=$(on "$node" <<<'systemctl --failed --no-legend --plain | cut -d" " -f1')
        [ -z "$failed" ] || die "$node has failed units: $(echo "$failed" | tr '\n' ' ')"
        ok "no failed units on $node"

        # 8. restore
        echo "== restoring $node (moving back: ''${origin:-nothing})"
        if [ $rebuilt = 0 ]; then
          ctl <<<"incus cluster restore $node --force --quiet"
        else
          # What `incus cluster restore` does for evacuate mode "migrate":
          # stop, move (Ceph-backed, so only the database record moves),
          # start, and drop the origin marker.
          for inst in $origin; do
            ctl <<<"incus stop $inst --force 2>/dev/null; incus move $inst --target $node && incus config unset $inst volatile.evacuate.origin && incus start $inst" \
              || die "moving $inst back to $node failed -- check 'incus list $inst'"
            ok "$inst moved back to $node"
          done
        fi

        # 9. everything came back
        echo "== checks after restoring"
        st=$(ctl <<<'incus cluster list -f json' | jq -r --arg n "$node" '.[] | select(.server_name==$n) | .status')
        [ "$st" = Online ] || die "$node is '$st' after restore"
        ok "$node is Online"
        for inst in $origin; do
          st=$(ctl <<<"incus list $inst -f json" | jq -r '.[0] | "\(.status) \(.location)"')
          if [ "$st" = "Running $node" ]; then ok "$inst running on $node"
          else fail "$inst is '$st'"; fi
        done
        ceph_wait_healthy || die "ceph unhealthy after restore"

        # 10. leftover blocklist entries (informational: each names one old client instance, which restarted processes never reuse, and they expire after 24 hours)
        bl=$(ctl <<<'ceph --id status osd blocklist ls 2>/dev/null' | grep -F "[$(mesh_of "$node")]" || true)
        if [ -n "$bl" ]; then
          echo "== Ceph blocklist entries for $node (from fencing it while it was gone; harmless, expire on their own after 24 h):"
          echo "$bl"
        fi
        echo "restore of $node complete"
      }

      # ------------------------------------------------------------------ replace-osd
      cmd_replace_osd() {
        local node=''${1:-} id=''${2:-} disk=''${3:-} host down configured used script confirm
        [ -n "$node" ] && [ -n "$id" ] && [ -n "$disk" ] \
          || die "usage: cluster replace-osd <node> <osd-id> /dev/disk/by-id/<new-disk>"
        is_node "$node" || die "unknown node $node"
        echo "== checks before replacing osd.$id on $node"

        host=$(ctl <<<"ceph --id status osd find $id -f json" | jq -r '.crush_location.host // empty')
        [ "$host" = "$node" ] || die "osd.$id is on ''${host:-nowhere}, not $node"
        ok "osd.$id lives on $node"

        # The config has to describe the hardware first, so the next rebuild of
        # this node agrees with what's on it.
        configured=$(field "$node" 3)
        [[ ",$configured," == *",$disk,"* ]] || die "$disk isn't in $node's osdDisks. Update modules/cluster/_hosts.nix (replace the dead disk's path), deploy $node, then run this again."
        ok "$disk is in $node's osdDisks"

        on "$node" <<<"test -b '$disk'" || die "$disk doesn't exist on $node"
        # Never wipe a disk a *different* live OSD is using (e.g. a typo'd osd-a
        # for osd-b): compare the kernel device name against every other OSD on
        # this host, from Ceph's own metadata.
        local kname others_on_disk
        kname=$(on "$node" <<<"basename \"\$(readlink -f '$disk')\"")
        others_on_disk=$(ctl <<<"ceph --id status osd metadata -f json" | jq -r \
          --arg h "$node" --arg k "$kname" --argjson id "$id" \
          '.[] | select(.hostname==$h and .id!=$id) | select((.devices // "") | split(",") | index($k)) | "osd.\(.id)"')
        [ -z "$others_on_disk" ] || die "$disk ($kname) is in use by $others_on_disk, not osd.$id -- wrong disk?"
        used=$(on "$node" <<<"lsblk -rno FSTYPE '$disk' | grep -v '^$' || true")
        [ -z "$used" ] || info "$disk has signatures ($used) -- they will be WIPED"
        ok "$disk present on $node"

        # Every *other* OSD must be up: rebuilding while another copy is missing
        # risks the data that only lives there.
        down=$(ctl <<<'ceph --id status osd dump -f json' | jq -r --argjson id "$id" '.osds[] | select(.osd != $id and .up == 0) | "osd.\(.osd)"')
        [ -z "$down" ] || die "other OSDs are down ($down) -- fix those first"
        ok "every other OSD is up"

        echo
        echo "This destroys osd.$id (keeping its id) and WIPES $disk on $node."
        read -r -p "Type the disk path again to continue: " confirm
        [ "$confirm" = "$disk" ] || die "cancelled"

        script=$(cat <<EOF
      set -euo pipefail
      id=$id; disk='$disk'
      ceph osd out \$id || true
      systemctl stop ceph-osd-\$id || true
      ceph osd destroy \$id --yes-i-really-mean-it
      # the old LV may be gone with the dead disk; clear what's left of it
      ceph-volume lvm zap --osd-id \$id --destroy 2>/dev/null || true
      rm -rf /var/lib/ceph/osd/ceph-\$id
      ceph-volume lvm zap --destroy "\$disk"
      ceph-volume lvm prepare --objectstore bluestore --no-systemd --osd-id \$id --data "\$disk"
      fsid=\$(cat /var/lib/ceph/osd/ceph-\$id/fsid)
      ceph-volume lvm deactivate \$id \$fsid
      ceph-volume lvm activate --no-tmpfs --no-systemd \$id \$fsid
      sync
      systemctl start ceph-osd-\$id
      ceph osd in \$id
      EOF
      )
        echo "== rebuilding osd.$id on $node (sudo password for shot@$node)"
        on_root "$node" "$script" || die "rebuild failed -- see output above, and 'cluster debug'"
        echo "== waiting for backfill"
        ceph_wait_healthy || die "ceph unhealthy after rebuild"
        echo "osd.$id rebuilt on $disk"
      }

      case ''${1:-} in
        debug)       shift; cmd_debug "$@" ;;
        restore)     shift; cmd_restore "$@" ;;
        replace-osd) shift; cmd_replace_osd "$@" ;;
        *) sed -n '2,10p' "$0" 2>/dev/null || true
           echo "usage: cluster debug | restore <node> | replace-osd <node> <osd-id> <disk>" >&2; exit 1 ;;
      esac
    '';
  };
in {
  flake.nixosModules.clusterTools = { config, pkgs, ... }: {
    environment.systemPackages = [ (mkCluster { inherit pkgs config; }) ];
  };
}
