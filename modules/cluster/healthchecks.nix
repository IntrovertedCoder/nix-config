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
  #                    running (any instance, so new services are covered:
  #                    Incus keeps volatile.last_state.power at RUNNING when
  #                    an instance dies with its node, STOPPED when you stop
  #                    it yourself).
  #                    Any node's ping counts; when none sees it fine the
  #                    check goes quiet (and alerts after its grace time),
  #                    and each node logs what it saw wrong to the check
  #
  # Checks are created by their first ping (?create=1); their period and
  # grace time are set on the healthchecks.io page, and its Discord
  # integration posts to the action-required channel.
  flake.nixosModules.clusterHealthchecks = { config, lib, pkgs, ... }: let
    inherit (config.var.cluster) name host;
    secret = "secrets/cluster-healthchecks-ping-key.age";
    shared = builtins.elem host.hostKey
      ((import ../../secrets.nix).${secret}.publicKeys or []);

    ping = pkgs.writeShellApplication {
      name = "cluster-healthchecks";
      runtimeInputs = with pkgs; [
        coreutils gnugrep gnused curl jq ceph config.virtualisation.incus.clientPackage
      ];
      text = /* bash */ ''
        KEY=$(cat ${config.age.secrets.cluster-healthchecks-ping-key.path})
        # hc <check>[/fail|/log], the message on stdin
        hc() {
          curl -fsS -m 15 --retry 3 -o /dev/null --data-binary @- \
            "https://hc-ping.com/$KEY/$1?create=1"
        }

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
          down=$(jq -r '.[] | select(.config["volatile.last_state.power"] == "RUNNING" and .status != "Running") | "\(.name) \(.status) on \(.location)"' <<<"$i")
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
  };
}
