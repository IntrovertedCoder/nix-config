{ inputs, lib, ... }: let
  hosts = import ./_hosts.nix;
  meshNet = "fd9a:7af:74af:ff::/64";
  # Public half of secrets/cluster-ssh-key.age.
  clusterSshPub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH8E4sA4+wHcXXN7kGC+E7kkoVDzp75hFzCspGCETyVP cluster-mesh";

  # Two programs, installed on every cluster node (Bash `${...}` is written
  # `''${...}` inside these Nix strings):
  #
  #   cluster        what you run, as shot: debug / restore / replace-osd
  #   cluster-agent  the only thing one node can run on another
  #
  # `cluster` asks each node for named actions ("report", "incus-members",
  # "restore test-node2", ...). For this node it runs cluster-agent itself;
  # for the others it SSHes over the mesh to the cluster-agent user, whose
  # key only ever runs cluster-agent (a forced command), and cluster-agent
  # only runs the actions listed in it, with checked arguments. So a node --
  # or someone who got shot's key file on one -- can't run anything else on
  # the others. The only root step (replace-osd's disk wipe) runs on the
  # node with the disk, through sudo with shot's password.
  #
  # Every command resolves to a pinned Nix store path: each program's tools
  # are its PATH, and nothing depends on a node's login PATH. The CLIs come
  # from the same packages the services run, so e.g. the incus client always
  # matches the daemon.

  mkAgent = { pkgs, config }: pkgs.writeShellApplication {
    name = "cluster-agent";
    runtimeInputs = with pkgs; [
      coreutils gnugrep gawk gnused jq util-linux procps iproute2 iputils
      ceph                                       # ceph, rbd
      config.virtualisation.incus.clientPackage  # incus
      frr                                        # vtysh
      config.services.chrony.package             # chronyc
      config.systemd.package                     # systemctl, journalctl
    ];
    text = /* bash */ ''
      NODES=(${lib.concatStringsSep " " (lib.attrNames hosts)})
      OSD_DISKS=(${lib.escapeShellArgs config.var.cluster.host.osdDisks})
      # Which node's router holds the gateway, from its MAC in the neighbour
      # table (router.nix: LAN MACs end in the node id) -- no root. Ping first:
      # a stopped router's MAC lingers there as STALE, which looked alive.
      MGMT_IF=br-trunk.${toString config.var.cluster.host.vlans.trusted}
      GATEWAY=${(import ./_lan.nix).segments.trusted.v4}.1
      gateway_router() {
        local mac id
        ping -c1 -W1 -I "$MGMT_IF" "$GATEWAY" >/dev/null 2>&1 || return 1
        mac=$(ip -4 neigh show "$GATEWAY" dev "$MGMT_IF" | awk '/lladdr/ && !/FAILED|INCOMPLETE/ {print $3}')
        [ -n "$mac" ] || return 1
        id=$(( 16#''${mac##*:} ))
        case $id in
          ${lib.concatStrings (lib.mapAttrsToList (n: h: "${toString h.id}) echo ${n} ;; ") hosts)}
          *) echo "unknown ($mac)" ;;
        esac
      }

      # cluster-agent -- the actions one cluster node may ask another for (see
      # tools.nix). Runs as the cluster-agent user, as the forced command of
      # the mesh SSH key, or as shot when `cluster` asks its own node.
      #
      # Read-only, on this node:   ping attention report mesh-ups stale-procs
      #                            incus-active failed-units disk-info <osd disk>
      #                            instance-here <instance>
      # Read-only, cluster-wide:   summary cluster-report incus-members
      #                            incus-instances incus-answers <node>
      #                            ceph <query> [osd id]
      #                            instance-report <instance>
      # Changes:                   restore <node>
      #                            move-home <instance> <node>
      #
      # Every argument is checked: node names against the cluster, disks
      # against this host's osdDisks, the rest against a strict pattern.

      die() { printf 'cluster-agent: %s\n' "$*" >&2; exit 1; }

      # Over SSH the request is in SSH_ORIGINAL_COMMAND (one line, split on
      # whitespace -- never evaluated by a shell); run locally, it's "$@".
      req=()
      if [ -n "''${SSH_ORIGINAL_COMMAND+set}" ]; then
        read -r -a req <<<"$SSH_ORIGINAL_COMMAND" || true
        logger -t cluster-agent -- "from ''${SSH_CLIENT%% *}: ''${req[*]}"
      else
        req=("$@")
      fi
      verb=''${req[0]:-}
      nargs=$(( ''${#req[@]} - 1 ))
      args() { [ "$nargs" -eq "$1" ] || die "$verb takes $1 argument(s)"; }

      is_node() { local n; for n in "''${NODES[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1; }
      node_arg() { is_node "$1" || die "unknown node: $1"; }
      inst_arg() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || die "bad instance name: $1"; }
      osd_disk_arg() {
        local d; for d in "''${OSD_DISKS[@]}"; do [ "$d" = "$1" ] && return 0; done
        die "$1 isn't one of this host's osdDisks"
      }

      c() { echo "\$ $*"; "$@" 2>&1; echo; }

      case $verb in
        ping) args 0 ;;

        # Summary lines for this node: hardware report verdict and attention
        # list (from cluster-hwcheck, see health.nix), its age, failed units, mesh.
        attention)
          args 0
          r=/run/cluster-health/report.txt
          if [ -r "$r" ]; then
            age=$(( ( $(date +%s) - $(stat -c %Y "$r") ) / 60 ))
            sed -n '/^ATTENTION:/,/^$/p' "$r" | tail -n +2 | grep -v '^  none$' | grep -v '^$' | sed 's/^  //' || true
            [ "$age" -gt 40 ] && echo "WARN  hardware report is ''${age} min old (is cluster-hwcheck.timer running?)"
          else
            echo "WARN  no hardware report yet (cluster-hwcheck runs 2 min after boot, then every 15 min)"
          fi
          for u in $(systemctl --failed --no-legend --plain | cut -d' ' -f1); do echo "FAIL  failed unit: $u"; done
          [ "$(systemctl is-active mesh-online)" = active ] || echo "FAIL  mesh-online is not active"
          [ "$(systemctl is-active microvm@router)" = active ] || echo "FAIL  this node's router VM (microvm@router) is not running"
          gateway_router >/dev/null || echo "FAIL  no router answers as the gateway $GATEWAY -- no internet for the LAN or this node"
          [ -e /run/mesh-fence/fenced ] && echo "FAIL  this node is self-fenced: cut off from the mesh, its instances killed (mesh-fence)"
          [ -e /run/mesh-fence/stale-ceph-client ] && echo "WARN  this node's kernel Ceph client is blocklisted (healing took its disks): reboot it before cluster restore"
          # update.nix: kept until this node updates fine or `cluster-update release`
          [ -r /var/lib/cluster-update-status/problem ] && echo "WARN  update: $(cat /var/lib/cluster-update-status/problem) (sudo cluster-update status)"
          true
          ;;

        report)
          args 0
          c uptime
          c systemctl is-active mesh-online frr ceph.target incus tailscaled chronyd microvm@router
          echo "\$ gateway $GATEWAY is held by the router on: $(gateway_router || echo "nobody (no router answering)")"; echo
          c ip -br addr
          c vtysh -c "show openfabric neighbor"
          c vtysh -c "show ipv6 route openfabric"
          c vtysh -c "show openfabric topology"
          c journalctl -b -u mesh-online --no-pager -n 10 -o short-iso
          c chronyc -n tracking
          c chronyc -n sources   # -n: no DNS, which is down with the routers
          c systemctl --failed --no-legend
          c rbd showmapped
          c journalctl -b -p warning --since -2h --no-pager -n 40 -o short-iso -u 'ceph*' -u incus -u frr -u mesh-online -u chronyd
          # healing/evacuation are logged at info level, so the filter above misses them
          c journalctl -u incus --no-pager -n 30 -o short-iso
          # unfiltered kernel errors (the hardware report hides e.g. RBD errors)
          c journalctl -k -b -p err --no-pager -n 30 -o short-iso
          echo "\$ cat /run/cluster-health/report.txt   # hardware, from cluster-hwcheck"
          cat /run/cluster-health/report.txt 2>&1
          ;;

        mesh-ups)  # OpenFabric neighbours Up, or 0 unless mesh-online is active
          args 0
          if systemctl is-active --quiet mesh-online; then
            vtysh -c "show openfabric neighbor" | grep -c " Up " || true
          else echo 0; fi
          ;;

        stale-procs)  # containers, VMs, RBD mappings still on this node (Incus's own
                      # qemu only -- the router VM runs qemu too, in microvm@router)
          args 0
          # 4th: 1 while this node's kernel Ceph client is stale (blocklisted
          # when healing took its disks); mesh-fence (incus.nix, root) keeps
          # the flag, since only root can see the client.
          echo "$(pgrep -c -f '^\[lxc monitor\]' || true) $(pgrep -c --cgroup /system.slice/incus.service qemu-system || true) $(rbd showmapped 2>/dev/null | tail -n +2 | wc -l) $([ -e /run/mesh-fence/stale-ceph-client ] && echo 1 || echo 0)"
          ;;

        incus-active) args 0; systemctl is-active --quiet incus ;;
        failed-units) args 0; systemctl --failed --no-legend --plain | cut -d" " -f1 ;;

        disk-info)  # "<kernel name> <signatures...>" of one of this host's OSD disks
          args 1; disk=''${req[1]}; osd_disk_arg "$disk"
          [ -b "$disk" ] || die "$disk doesn't exist"
          echo "$(basename "$(readlink -f "$disk")") $(lsblk -rno FSTYPE "$disk" | grep -v '^$' | tr '\n' ' ' || true)"
          ;;

        summary)  # cluster-wide lines for debug's Attention list
          args 0
          h=$(ceph --id status health 2>&1 || true)
          [ "''${h%% *}" = HEALTH_OK ] || echo "ceph: $h"
          crashes=$(ceph --id status crash ls-new 2>/dev/null | tail -n +2 | wc -l)
          [ "$crashes" -gt 0 ] && echo "ceph: $crashes recent daemon crashes not yet archived (ceph crash ls-new)"
          incus cluster list -f csv -c ns 2>/dev/null | awk -F, '$2 != "ONLINE" {print "incus: member " $1 " is " $2}'
          true
          ;;

        cluster-report)
          args 0
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
          ;;

        incus-members)   args 0; incus cluster list -f json ;;
        incus-instances) args 0; incus list -f json ;;
        incus-answers)   args 1; node_arg "''${req[1]}"; incus info --target "''${req[1]}" >/dev/null ;;

        ceph)  # read-only queries with the client.status key
          [ "$nargs" -ge 1 ] || die "ceph needs a query"
          q=''${req[1]}
          case $q in
            osd-find)
              args 2; [[ ''${req[2]} =~ ^[0-9]{1,5}$ ]] || die "bad osd id: ''${req[2]}"
              ceph --id status osd find "''${req[2]}" -f json ;;
            health-json)   args 1; ceph --id status health detail -f json ;;
            health-detail) args 1; ceph --id status health detail ;;
            status)        args 1; ceph --id status -s ;;
            osd-stat-json) args 1; ceph --id status osd stat -f json ;;
            quorum-json)   args 1; ceph --id status quorum_status -f json ;;
            osd-metadata-json) args 1; ceph --id status osd metadata -f json ;;
            osd-dump-json) args 1; ceph --id status osd dump -f json ;;
            blocklist)     args 1; ceph --id status osd blocklist ls 2>/dev/null ;;
            *) die "unknown ceph query: $q" ;;
          esac
          ;;

        restore)  # `incus cluster restore` -- cluster restore checks first
          args 1; node_arg "''${req[1]}"
          incus cluster restore "''${req[1]}" --force --quiet
          ;;

        move-home)
          # What `incus cluster restore` does for evacuate mode "migrate", for a
          # rebuilt node (cluster restore step 8): stop, move (Ceph-backed, so
          # only the database record moves), start, drop the origin marker.
          # Only for an instance that really was evacuated from that node.
          args 2; inst=''${req[1]}; node=''${req[2]}; inst_arg "$inst"; node_arg "$node"
          origin=$(incus list -f json | jq -r --arg i "$inst" '.[] | select(.name==$i) | .config["volatile.evacuate.origin"] // empty')
          [ "$origin" = "$node" ] || die "$inst wasn't evacuated from $node (origin: ''${origin:-none})"
          incus stop "$inst" --force 2>/dev/null || true
          incus move "$inst" --target "$node"
          incus config unset "$inst" volatile.evacuate.origin
          incus start "$inst"
          ;;

        instance-report)  # one instance, cluster-wide (cluster vm-debug)
          args 1; inst=''${req[1]}; inst_arg "$inst"
          echo "\$ incus list -f json   # this instance; user.* and cloud-init.* values hidden"
          incus list -f json | jq --arg i "$inst" '.[] | select(.name == $i)
            | .expanded_config |= with_entries(if (.key | test("^(user|cloud-init)\\.")) then .value = "(hidden)" else . end)
            | {name, type, status, location, profiles, created_at, last_used_at, expanded_config, expanded_devices}' 2>&1
          echo
          c incus info "$inst" --show-log
          c incus console "$inst" --show-log
          c incus operation list
          c incus warning list
          ;;

        instance-here)  # one instance on this node: "mapped <rbd image>" and
                        # "process <pid>" lines, then "--- log" and its
                        # journal lines (incus, healing, fencing; last 7 days)
          args 1; inst=''${req[1]}; inst_arg "$inst"
          rbd showmapped --format json 2>/dev/null | jq -r --arg i "$inst" \
            '.[] | select(.name | test("^(container|virtual-machine)_" + $i + "(\\.block)?$")) | "mapped \(.name) \(.device)"' || true
          pgrep -f "^\[lxc monitor\] /var/lib/incus/containers $inst\$" | sed 's/^/process /' || true
          pgrep --cgroup /system.slice/incus.service -f "qemu-system.* -name $inst( |\$)" | sed 's/^/process /' || true
          echo "--- log"
          journalctl --since -7d --no-pager -o short-iso \
              -u incus -u incus-healing-arm -u incus-autostart-recover -u mesh-fence -u incus-stale-cleanup 2>/dev/null \
            | grep -E "(^|[^A-Za-z0-9_.-])$inst([^A-Za-z0-9_-]|\$)" | tail -n 25 || true
          ;;

        "") die "no action given" ;;
        *) die "unknown action: $verb" ;;
      esac
    '';
  };

  mkCluster = { pkgs, config, agent }: let
    # For replace-osd's root step, run through sudo (which resets PATH).
    rootTools = with pkgs; [ coreutils ceph lvm2 util-linux config.systemd.package ];
  in pkgs.writeShellApplication {
    name = "cluster";
    runtimeInputs = with pkgs; [
      coreutils gnugrep gnused jq
      config.programs.ssh.package  # ssh, to the other nodes' cluster-agent
      agent                        # cluster-agent, for this node
    ];
    text = /* bash */ ''
      CLUSTER_NODES=(${lib.concatStringsSep " " (lib.mapAttrsToList (name: h:
        "'${name}=${toString h.id}=${toString (builtins.length h.ring)}=${lib.concatStringsSep "," h.osdDisks}'"
      ) hosts)})
      SELF=${config.networking.hostName}
      SSH_KEY=${config.age.secrets.cluster-ssh-key.path}
      SUDO=${config.security.wrapperDir}/sudo
      BASH_BIN=${pkgs.bash}/bin/bash
      ROOT_PATH=${lib.makeBinPath rootTools}

      usage() {
        cat >&2 <<'EOF'
      cluster -- day-to-day operations for the Elements cluster. Runs as shot on
      any cluster node (from a workstation: ssh -p 20530 shot@<node> cluster ...):

        cluster debug                                  health report to paste into a chat
        cluster vm-debug <instance>                    why one instance (container or VM) isn't
                                                       running, or is where it is
        cluster restore <node>                         bring an evacuated node back, safely
        cluster replace-osd <node> <osd-id> <disk>     rebuild an OSD on a replacement disk
                                                       (run it on <node>, with ssh -t)
        cluster check-ssh                              can this node reach the others?
      EOF
        exit 1
      }

      # Other nodes are asked over SSH on the mesh (fd9a:7af:74af:ff::<id>,
      # port 20530) as the cluster-agent user, with a key only the nodes have,
      # accepted only from mesh addresses. No internet or Tailscale needed --
      # only the ring links. Read-only Ceph access uses client.status (no root).
      #
      # Set by tools.nix from modules/cluster/_hosts.nix:
      #   CLUSTER_NODES  "name=id=ringLinks=disk1,disk2" per node, in id order

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

      # on <node> <action> [args...]: ask <node>'s cluster-agent for one action
      # (the list is in cluster-agent). This node: run it here, as shot.
      # Others: over the mesh, within ON_TIMEOUT seconds (default 60).
      # -F none: no user/system ssh_config can change what this does. Host
      # keys come only from /etc/ssh/ssh_known_hosts (tools.nix, from
      # _hosts.nix), and nothing is ever added. BatchMode: fail instead of
      # prompting if the key is refused. BindAddress: always connect from our
      # own mesh address, the only source the key is accepted from.
      on() {
        local n=$1; shift
        if [ "$n" = "$SELF" ]; then cluster-agent "$@"
        else
          timeout "''${ON_TIMEOUT:-60}" ssh -F none -p 20530 -i "$SSH_KEY" \
            -o IdentitiesOnly=yes -o BatchMode=yes \
            -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 -o BindAddress="$(mesh_of "$SELF")" \
            "cluster-agent@$(mesh_of "$n")" "$*" </dev/null
        fi
      }
      reachable() { on "$1" ping >/dev/null 2>&1; }

      # A node to ask cluster-wide questions: this one if its Incus answers (it
      # may be the broken one), else the first other node that does.
      CTRL=""
      control() {
        [ -n "$CTRL" ] && return 0
        local n
        for n in "$SELF" $(node_names); do
          if on "$n" incus-members >/dev/null 2>&1; then CTRL=$n; return 0; fi
        done
        die "no cluster node answers (incus cluster list) -- run 'cluster debug' to see why"
      }
      ctl() { control; on "$CTRL" "$@"; }   # cluster-wide action

      # ------------------------------------------------------------------ debug
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
        summary=$(ctl summary 2>/dev/null || true)
        if [ -n "$summary" ]; then echo "$summary"; any=1; fi
        for n in $(node_names); do
          if ! reachable "$n"; then echo "$n: FAIL  unreachable over SSH on the mesh"; any=1; continue; fi
          lines=$(on "$n" attention 2>/dev/null || true)
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
        ctl cluster-report 2>&1 || true
        echo '```'
        for n in $(node_names); do
          echo
          echo "### $n"
          echo '```'
          if ! reachable "$n"; then echo "UNREACHABLE over SSH on the mesh"; echo '```'; continue; fi
          on "$n" report 2>&1 || true
          echo '```'
        done
      }

      # ------------------------------------------------------------------ vm-debug
      # One instance (container or VM): why isn't it running, or why is it
      # where it is. Like debug: what needs attention first, then the
      # evidence -- Incus's view (via one node), then each node's (is its
      # disk mapped there, does a process run there, what Incus, healing and
      # fencing logged about it).
      cmd_vm_debug() {
        [ $# -eq 1 ] || usage
        local inst=$1 j members st last loc locst origin type n l mapped procs any=0
        [[ $inst =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || die "bad instance name: $inst"
        control
        j=$(ctl incus-instances | jq --arg i "$inst" '.[] | select(.name == $i)')
        [ -n "$j" ] || die "no instance called $inst -- there are: $(ctl incus-instances | jq -r '[.[].name] | join(" ")')"
        members=$(ctl incus-members)
        st=$(jq -r .status <<<"$j")
        last=$(jq -r '.config["volatile.last_state.power"] // "unknown"' <<<"$j")
        loc=$(jq -r .location <<<"$j")
        origin=$(jq -r '.config["volatile.evacuate.origin"] // empty' <<<"$j")
        type=$(jq -r .type <<<"$j")
        locst=$(jq -r --arg n "$loc" '.[] | select(.server_name == $n) | "\(.status) (\(.message))"' <<<"$members")

        # What each node has of it: "mapped ..."/"process ..." lines, the log after "--- log"
        declare -A here
        for n in $(node_names); do
          if reachable "$n"; then here[$n]=$(on "$n" instance-here "$inst" 2>&1 || true)
          else here[$n]=unreachable; fi
        done

        echo "## Elements instance debug report: $inst"
        echo
        echo "Generated $(date -u '+%F %T UTC') from $SELF; Incus asked via $CTRL."
        echo
        echo "### Attention"
        echo '```'
        echo "$inst ($type) is $st on $loc; the state Incus last recorded for it: $last"
        if [ "$st" != Running ]; then
          if [ "$last" = RUNNING ]; then echo "FAIL  it should be running (last recorded state RUNNING) but is $st"; any=1
          else echo "info  stopped on purpose (last recorded state $last) -- not an outage"; fi
        fi
        case $locst in
          Online*) ;;
          "") echo "FAIL  its node $loc isn't an Incus member"; any=1 ;;
          *) echo "FAIL  its node $loc is $locst"; any=1 ;;
        esac
        if [ -n "$origin" ]; then
          echo "WARN  it was evacuated from $origin (healing or evacuation): 'cluster restore $origin' moves it back once that node is fine"; any=1
        fi
        for n in $(node_names); do
          if [ "''${here[$n]}" = unreachable ]; then
            echo "WARN  $n is unreachable over the mesh: can't see whether it still runs $inst or holds its disk"; any=1; continue
          fi
          mapped=$(sed '/^--- log$/q' <<<"''${here[$n]}" | awk '$1 == "mapped" {printf "%s%s", sep, $2; sep=", "}')
          procs=$(sed '/^--- log$/q' <<<"''${here[$n]}" | awk '$1 == "process" {printf "%s%s", sep, $2; sep=", "}')
          if [ "$n" != "$loc" ]; then
            [ -z "$procs" ] || { echo "FAIL  a copy still runs on $n (pid $procs), not on $loc where Incus has it"; any=1; }
            [ -z "$mapped" ] || { echo "FAIL  its disk is still mapped on $n ($mapped): $n kept it without cleaning up, so it can't safely run on $loc (rebooting $n clears it)"; any=1; }
          elif [ "$st" = Running ] && [ -z "$procs" ]; then
            echo "WARN  Incus says Running, but no process for it runs on $loc"; any=1
          elif [ "$st" != Running ] && [ -n "$procs" ]; then
            echo "WARN  Incus says $st, but a process for it still runs on $loc (pid $procs)"; any=1
          fi
        done
        if [ "''${here[$loc]:-unreachable}" != unreachable ]; then
          while IFS= read -r l; do [ -n "$l" ] && { echo "$loc: $l"; any=1; }; done < <(on "$loc" attention 2>/dev/null || true)
        fi
        [ $any = 0 ] && echo "nothing -- it is where Incus says, in the state it should be"
        echo '```'

        echo
        echo "### Incus (via $CTRL)"
        echo '```'
        ctl instance-report "$inst" 2>&1 || true
        echo '```'
        for n in $(node_names); do
          echo
          echo "### $n"
          echo '```'
          if [ "''${here[$n]}" = unreachable ]; then echo "UNREACHABLE over SSH on the mesh"; echo '```'; continue; fi
          sed '/^--- log$/q' <<<"''${here[$n]}" | grep -v '^--- log$' || echo "no disk mapped and no process for $inst here"
          echo "--- what Incus, healing and fencing logged about $inst here (last 7 days, newest last)"
          sed '1,/^--- log$/d' <<<"''${here[$n]}"
          echo '```'
        done
      }

      # ------------------------------------------------------------------ check-ssh
      # Every other node's cluster-agent answers over SSH on the mesh -- the
      # path every other command here depends on. The bootstrap scripts run
      # it on each node.
      cmd_check_ssh() {
        local n err bad=0
        for n in $(node_names); do
          [ "$n" = "$SELF" ] && continue
          if err=$(on "$n" ping 2>&1 >/dev/null); then ok "$SELF -> $n"
          else fail "$SELF -> $n: no answer over SSH on the mesh ($(tail -n1 <<<"''${err:-timed out}"))"; bad=1
          fi
        done
        return $bad
      }

      # ------------------------------------------------------------------ restore
      ceph_wait_healthy() {  # ceph_wait_healthy [node-that-must-be-in-quorum]
        local start now status checks bad osds q total up inn
        start=$(date +%s)
        while :; do
          status=$(ctl ceph health-json)
          osds=$(ctl ceph osd-stat-json | jq -r '"\(.num_osds) \(.num_up_osds) \(.num_in_osds)"')
          q=$(ctl ceph quorum-json | jq -r '.quorum_names | join(",")')
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
            ctl ceph health-detail >&2
            return 1
          fi
          now=$(date +%s)
          if [ $((now - start)) -gt "$WAIT_SECS" ]; then
            fail "ceph still not healthy after ''${WAIT_SECS}s"; ctl ceph status >&2; return 1
          fi
          info "waiting for ceph ($up/$total OSDs up, $inn in; $(echo "$checks" | tr '\n' ' '))"
          sleep 15
        done
      }

      cmd_restore() {
        local node=''${1:-} members st others origin stale ring ups failed inst bl lxcs qemus maps rebuilt m
        [ -n "$node" ] || die "usage: cluster restore <node>"
        is_node "$node" || die "unknown node $node (known: $(node_names | tr '\n' ' '))"
        echo "== checks before restoring $node"

        # 1. right node, nothing else down
        members=$(ctl incus-members)
        st=$(jq -r --arg n "$node" '.[] | select(.server_name==$n) | .status' <<<"$members")
        origin=$(ctl incus-instances | jq -r --arg n "$node" '.[] | select(.config["volatile.evacuate.origin"]==$n) | .name')
        # Those already stopped (e.g. kept as a way back) come back stopped.
        stopped=$(ctl incus-instances | jq -r --arg n "$node" '.[] | select(.config["volatile.evacuate.origin"]==$n and .status=="Stopped") | .name')
        # A rebuilt node (cluster-rebuild) rejoins Incus as a new, Online
        # member, so its healed-away instances still name it as their origin
        # but `incus cluster restore` has nothing to restore. Move those back
        # by hand instead (step 8).
        if [ "$st" = Online ] && [ -n "$origin" ]; then
          rebuilt=1
        else
          rebuilt=0
          [ "$st" = Evacuated ] || die "$node is '$st', not Evacuated, and no instances were evacuated from it -- nothing to restore"
        fi
        # Another Evacuated member is fine if it's up, just drained (e.g.
        # several healed at once after a power cut) -- but a member that died
        # after it was healed away from shows Evacuated too, so ask it.
        others=$(jq -r --arg n "$node" '.[] | select(.server_name!=$n and .status!="Online" and .status!="Evacuated") | "\(.server_name)=\(.status)"' <<<"$members")
        for m in $(jq -r --arg n "$node" '.[] | select(.server_name!=$n and .status=="Evacuated") | .server_name' <<<"$members"); do
          ctl incus-answers "$m" 2>/dev/null || others="$others $m=Evacuated,not-answering"
        done
        [ -z "$others" ] || die "other members are down ($others) -- fix those first; the cluster has no spare"
        if [ $rebuilt = 1 ]; then
          ok "$node is Online (rebuilt) with instances still evacuated from it; no other member is down"
        else
          ok "$node is Evacuated, no other member is down"
        fi

        reachable "$node" || die "$node isn't reachable over SSH on the mesh"

        # 2. mesh
        ring=$(field "$node" 2)
        ups=$(on "$node" mesh-ups)
        [ "$ups" -ge "$ring" ] || die "$node mesh isn't up ($ups/$ring adjacencies; mesh-online must be active)"
        ok "mesh-online active, $ups/$ring OpenFabric neighbours Up"

        # 3+4. no stale instance copies: after a failure, Incus leaves the old
        # node's copies running (fenced, but alive) until it reboots.
        stale=$(on "$node" stale-procs)
        read -r lxcs qemus maps client <<<"$stale"
        if [ "$lxcs" != 0 ] || [ "$qemus" != 0 ] || [ "$maps" != 0 ]; then
          die "$node still has instance processes or RBD mappings ($lxcs containers, $qemus VMs, $maps mapped) -- probably stale copies from before it failed. Reboot $node, then run this again."
        fi
        ok "no instance processes or RBD mappings left on $node"
        # Healing blocklists the old node's kernel Ceph client, and it outlives
        # its last disk: every new map on that node then fails, so a restore
        # would move the instances back and fail to start them (seen in
        # testing). Only a reboot clears it. (Empty on a node still running
        # an older cluster-agent: treat as fine.)
        if [ "''${client:-0}" != 0 ]; then
          die "$node's kernel Ceph client was blocklisted when healing took its disks, and only a reboot clears it (mesh-fence normally reboots it by itself). Reboot $node, then run this again."
        fi
        ok "$node's kernel Ceph client is usable"

        # 5. ceph caught up, node's mon back in quorum
        ceph_wait_healthy "$node" || die "ceph isn't ready"

        # 6. incus
        on "$node" incus-active || die "incus isn't running on $node"
        ctl incus-answers "$node" || die "incus on $node doesn't answer"
        ok "incus active on $node and answering"

        # 7. healthy node
        failed=$(on "$node" failed-units)
        [ -z "$failed" ] || die "$node has failed units: $(echo "$failed" | tr '\n' ' ')"
        ok "no failed units on $node"

        # 8. restore (moving instances can take a while: 15 minutes, not 60 s)
        echo "== restoring $node (moving back: ''${origin:-nothing})" | tr '\n' ' '; echo
        if [ $rebuilt = 0 ]; then
          ON_TIMEOUT=900 ctl restore "$node"
        else
          for inst in $origin; do
            ON_TIMEOUT=900 ctl move-home "$inst" "$node" \
              || die "moving $inst back to $node failed -- check 'incus list $inst'"
            ok "$inst moved back to $node"
          done
        fi

        # 9. everything came back
        echo "== checks after restoring"
        st=$(ctl incus-members | jq -r --arg n "$node" '.[] | select(.server_name==$n) | .status')
        [ "$st" = Online ] || die "$node is '$st' after restore"
        ok "$node is Online"
        for inst in $origin; do
          st=$(ctl incus-instances | jq -r --arg i "$inst" '.[] | select(.name==$i) | "\(.status) \(.location)"')
          if [ "$st" = "Running $node" ]; then ok "$inst running on $node"
          elif [ "$st" = "Stopped $node" ] && grep -qx "$inst" <<<"$stopped"; then ok "$inst back on $node (stopped, as it was)"
          else fail "$inst is '$st'"; fi
        done
        ceph_wait_healthy || die "ceph unhealthy after restore"

        # 10. leftover blocklist entries (informational: each names one old client instance, which restarted processes never reuse, and they expire after 24 hours)
        bl=$(ctl ceph blocklist | grep -F "[$(mesh_of "$node")]" || true)
        if [ -n "$bl" ]; then
          echo "== Ceph blocklist entries for $node (from fencing it while it was gone; harmless, expire on their own after 24 h):"
          echo "$bl"
        fi
        echo "restore of $node complete"
      }

      # ------------------------------------------------------------------ replace-osd
      cmd_replace_osd() {
        local node=''${1:-} id=''${2:-} disk=''${3:-} host down configured dinfo kname used script confirm others_on_disk
        [ -n "$node" ] && [ -n "$id" ] && [ -n "$disk" ] \
          || die "usage: cluster replace-osd <node> <osd-id> /dev/disk/by-id/<new-disk>"
        is_node "$node" || die "unknown node $node"
        [[ $id =~ ^[0-9]{1,5}$ ]] || die "bad osd id: $id"
        # The wipe needs root, and root is only ever sudo with your password on
        # the node itself -- no node can get root on another.
        [ "$node" = "$SELF" ] || die "run this on $node itself: ssh -t -p 20530 shot@$node cluster replace-osd $node $id $disk"
        echo "== checks before replacing osd.$id on $node"

        host=$(ctl ceph osd-find "$id" | jq -r '.crush_location.host // empty')
        [ "$host" = "$node" ] || die "osd.$id is on ''${host:-nowhere}, not $node"
        ok "osd.$id lives on $node"

        # The config has to describe the hardware first, so the next rebuild of
        # this node agrees with what's on it.
        configured=$(field "$node" 3)
        [[ ",$configured," == *",$disk,"* ]] || die "$disk isn't in $node's osdDisks. Update modules/cluster/_hosts.nix (replace the dead disk's path), deploy $node, then run this again."
        ok "$disk is in $node's osdDisks"

        dinfo=$(on "$node" disk-info "$disk") || die "$disk doesn't exist on $node"
        read -r kname used <<<"$dinfo"
        # Never wipe a disk a *different* live OSD is using (e.g. a typo'd osd-a
        # for osd-b): compare the kernel device name against every other OSD on
        # this host, from Ceph's own metadata.
        others_on_disk=$(ctl ceph osd-metadata-json | jq -r \
          --arg h "$node" --arg k "$kname" --argjson id "$id" \
          '.[] | select(.hostname==$h and .id!=$id) | select((.devices // "") | split(",") | index($k)) | "osd.\(.id)"')
        [ -z "$others_on_disk" ] || die "$disk ($kname) is in use by $others_on_disk, not osd.$id -- wrong disk?"
        [ -z "$used" ] || info "$disk has signatures ($used) -- they will be WIPED"
        ok "$disk present on $node"

        # Every *other* OSD must be up: rebuilding while another copy is missing
        # risks the data that only lives there.
        down=$(ctl ceph osd-dump-json | jq -r --argjson id "$id" '.osds[] | select(.osd != $id and .up == 0) | "osd.\(.osd)"')
        [ -z "$down" ] || die "other OSDs are down ($down) -- fix those first"
        ok "every other OSD is up"

        echo
        echo "This destroys osd.$id (keeping its id) and WIPES $disk on $node."
        read -r -p "Type the disk path again to continue: " confirm
        [ "$confirm" = "$disk" ] || die "cancelled"

        script=$(cat <<EOF
      set -euo pipefail
      export PATH=$ROOT_PATH:\$PATH
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
        echo "== rebuilding osd.$id on $node (sudo password for shot)"
        "$SUDO" "$BASH_BIN" -c "$script" || die "rebuild failed -- see output above, and 'cluster debug'"
        echo "== waiting for backfill"
        ceph_wait_healthy || die "ceph unhealthy after rebuild"
        echo "osd.$id rebuilt on $disk"
      }

      case ''${1:-} in
        debug)       shift; cmd_debug "$@" ;;
        vm-debug)    shift; cmd_vm_debug "$@" ;;
        restore)     shift; cmd_restore "$@" ;;
        replace-osd) shift; cmd_replace_osd "$@" ;;
        check-ssh)   shift; cmd_check_ssh ;;
        *) usage ;;
      esac
    '';
  };
in {
  flake.nixosModules.clusterTools = { config, lib, pkgs, ... }: let
    agent = mkAgent { inherit pkgs config; };
  in {
    imports = [ inputs.agenix.nixosModules.default ];

    environment.systemPackages = [ (mkCluster { inherit pkgs config agent; }) agent ];

    # Read access for the cluster tool without root or wheel: the Ceph
    # status keyring (ceph.nix) and the hardware report (health.nix).
    users.groups.cluster-read = { };
    users.users.shot.extraGroups = [ "cluster-read" ];

    # The user other nodes log in as. Its only key runs cluster-agent and
    # nothing else (forced command; `restrict` also rules out a terminal and
    # any forwarding), and is accepted only from mesh addresses. Its groups
    # give the read access the actions need -- incus-admin is root-equivalent
    # for anyone who can run arbitrary incus commands, which is exactly what
    # the forced command prevents. sshd runs the forced command through the
    # login shell, so it needs a real one.
    users.groups.cluster-agent = { };
    users.users.cluster-agent = {
      isSystemUser = true;
      group = "cluster-agent";
      extraGroups = [ "cluster-read" "incus-admin" "frrvty" "systemd-journal" ];
      shell = pkgs.bashInteractive;
      home = "/var/lib/cluster-agent";  # the incus client keeps its config here
      createHome = true;
      openssh.authorizedKeys.keys = [
        ''restrict,from="${meshNet}",command="${lib.getExe agent}" ${clusterSshPub}''
      ];
    };

    # The key `cluster` uses to reach the other nodes' cluster-agent. Every
    # node has the same one, decrypted with its pre-seeded host key; readable
    # by shot, who runs `cluster`.
    age.secrets.cluster-ssh-key = {
      file = ../../secrets/cluster-ssh-key.age;
      owner = "shot";
      mode = "0400";
    };
    # Every node's host key at its mesh address, so ssh checks it strictly.
    programs.ssh.knownHosts = lib.mapAttrs (_: h: {
      hostNames = [ "[fd9a:7af:74af:ff::${toString h.id}]:20530" ];
      publicKey = h.hostKey;
    }) hosts;
    # A burst of failed logins from another node (e.g. after a key change)
    # must never get it banned.
    services.fail2ban.ignoreIP = [ meshNet ];
  };
}
