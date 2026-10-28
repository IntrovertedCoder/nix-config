{ lib, ... }: {
  # Outside alerting through healthchecks.io: a dead-man's switch, so the
  # alert comes from somewhere that isn't the cluster (or vmtest, which the
  # cluster will host). Every 5 minutes each node pings, with the ping key of
  # the project (secrets/cluster-healthchecks-ping-key.age):
  #
  #   <node>           it's up and reaches the internet; a /fail ping (an
  #                    alert right away) while its hardware check says FAIL
  #                    (health.nix), with the reasons
  #   elements-health  the whole cluster looks fine: Ceph HEALTH_OK, every
  #                    Incus member ONLINE, every instance that should run
  #                    running (_instance-down.nix, the same rule as
  #                    cluster debug's Attention list).
  #                    Any node's ping counts; when none sees it fine the
  #                    check goes quiet (and alerts after its grace time),
  #                    and each node logs what it saw wrong to the check
  #   elements-space   every node's disk space is fine (`cluster space`,
  #                    tools.nix: no WARN or FAIL about a node's own disks or
  #                    its Ceph disks, health.nix). Every 15 minutes, when the
  #                    hardware check has new numbers. Like elements-health:
  #                    each node asks every node, so any node's ping counts,
  #                    and what's wrong goes to the check's log. Its own
  #                    check, so a disk filling up for days doesn't hide an
  #                    outage behind a check that's already down.
  #
  # Checks are created by their first ping (?create=1); their period and
  # grace time are set on the healthchecks.io page, and its Discord
  # integration posts to the action-required channel.
  flake.nixosModules.clusterHealthchecks = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host;
    secret = "secrets/cluster-healthchecks-ping-key.age";
    instanceDown = import ./_instance-down.nix;
    shared = builtins.elem host.hostKey
      ((import ../../secrets.nix).${secret}.publicKeys or []);

    hc = /* bash */ ''
      KEY=$(cat ${config.age.secrets.cluster-healthchecks-ping-key.path})
      # hc <check>[/fail|/log], the message on stdin
      hc() {
        curl -fsS -m 15 --retry 3 -o /dev/null --data-binary @- \
          "https://hc-ping.com/$KEY/$1?create=1"
      }
    '';

    ping = pkgs.writeShellApplication {
      name = "cluster-healthchecks";
      runtimeInputs = with pkgs; [
        coreutils gnugrep gnused curl jq ceph config.virtualisation.incus.clientPackage
      ];
      text = hc + /* bash */ ''

        # This node, and its hardware check
        report=/run/cluster-health/report.txt
        if [ -r "$report" ] && [ "$(head -1 "$report")" = "STATUS: FAIL" ]; then
          sed -n '/^ATTENTION:/,/^---/p' "$report" | grep -v '^---' | hc ${name}/fail
        else
          uptime | hc ${name}
        fi

        # The cluster as this node sees it
        problems=()
        h=$(timeout 30 ceph health 2>&1) || true
        [ "$h" = HEALTH_OK ] || problems+=("ceph: ''${h:-no answer}")
        if m=$(timeout 30 incus cluster list -f csv -c n,s </dev/null 2>&1); then
          bad=$(grep -v ',ONLINE$' <<<"$m" || true)
          [ -z "$bad" ] || problems+=("incus members: $bad")
        else
          problems+=("incus: no answer")
        fi
        if i=$(timeout 30 incus list -f json </dev/null 2>/dev/null); then
          down=$(jq -r '.[] | ${instanceDown} | "\(.name) \(.status) on \(.location)"' <<<"$i")
          [ -z "$down" ] || problems+=("instances not running: $down")
        else
          problems+=("incus list: no answer")
        fi

        if [ ''${#problems[@]} -eq 0 ]; then
          echo "fine, seen from ${name}" | hc elements-health
        else
          printf '%s\n' "seen from ${name}:" "''${problems[@]}" | hc elements-health/log
        fi
      '';
    };

    space = pkgs.writeShellApplication {
      name = "cluster-healthchecks-space";
      runtimeInputs = with pkgs; [ coreutils curl util-linux ];
      text = hc + /* bash */ ''

        # As shot: the key that reaches the other nodes' cluster-agent is shot's.
        # Exit 1 means a problem, or that `cluster space` itself failed: both
        # go to the log, and the check goes quiet unless another node sees fine.
        if out=$(runuser -u shot -- ${lib.getExe config.var.cluster.tool} space 2>&1); then check=elements-space
        else check=elements-space/log; fi
        printf '%s\n' "$out" "-> $check"  # the journal: what was seen, and sent
        printf '%s\n' "seen from ${name}:" "$out" | hc "$check"
      '';
    };
  in lib.mkIf shared {
    age.secrets.cluster-healthchecks-ping-key.file = ../../${secret};

    systemd.services.cluster-healthchecks = {
      description = "Ping healthchecks.io: this node and the cluster";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe ping;
      };
    };
    systemd.timers.cluster-healthchecks = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "5min";
      };
    };

    systemd.services.cluster-healthchecks-space = {
      description = "Ping healthchecks.io: every node's disk space";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe space;
      };
    };
    # The hardware check's pace (health.nix): checking more often finds nothing new
    systemd.timers.cluster-healthchecks-space = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "15min";
      };
    };
  };
}
