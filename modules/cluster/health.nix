{ lib, ... }: {
  # Hardware health check on every cluster node: SMART, temperatures, fans,
  # throttling, memory errors, kernel hardware errors, disk space (its own
  # disks and its Ceph disks), ring links, unclean shutdowns, kernel crash
  # records, clock. Runs as root (SMART needs
  # it) every 15 minutes and writes /run/cluster-health/report.txt for group
  # cluster-read (tools.nix), which is what `cluster debug` reads -- so the
  # tool itself never needs root. Its disk-space problems also go to
  # space.txt beside it, for `cluster space` and elements-space
  # (healthchecks.nix). (Bash `${...}` is written `''${...}` inside the Nix
  # string.)
  flake.nixosModules.clusterHealth = { config, lib, pkgs, ... }: let
    report = "/run/cluster-health/report.txt";
    space = "/run/cluster-health/space.txt";

    # This node's Ceph disks: how full they are, and how full they'd be after
    # a failure. Each node holds one copy of everything in a 3-copy pool, so:
    #   - one of its disks fails: Ceph copies that disk's data onto the
    #     node's other disk(s). With two equal disks, the node has to stay
    #     under half of Ceph's warning level (85%) to take that.
    #   - another node fails: the 3-copy pools have nowhere to go (they run
    #     on two copies until it's back), but a pool with fewer copies than
    #     nodes (media, 2) gets the lost copies re-made on the other nodes.
    # A disk past Ceph's own warning level is FAIL (recovery stops at 90%,
    # every write at 95%); a failure that would push one past it is WARN.
    # In: $me (this node's CRUSH host), then on stdin `ceph osd df tree`,
    # `ceph osd dump`, `ceph pg ls` (JSON). Out: "say|WARN|FAIL<tab>text".
    cephSpace = pkgs.writeText "ceph-space.jq" /* jq */ ''
      def gib: . / 1048576 | (. * 10 | round) / 10;  # KiB -> GiB
      def pc: . * 100 | round;
      def fill: "\(pc)% full" + (if . >= 1 then ": it would not fit" else "" end);
      input as $tree | input as $dump | input as $pgs
      | $dump.nearfull_ratio as $near
      | "Ceph warns at \($near | pc)%, stops recovery at \($dump.backfillfull_ratio | pc)% and every write at \($dump.full_ratio | pc)%" as $limits
      | ($tree.nodes | map(select(.type == "host" and .kb > 0))) as $hosts
      | ($tree.nodes | map(select(.type == "osd")) | INDEX(.id)) as $osds
      | ([$hosts[] | .name as $n | .children[] | {key: tostring, value: $n}] | from_entries) as $hostOf
      | ($dump.pools | map({key: (.pool | tostring), value: .pool_name}) | from_entries) as $poolName
      | ($hosts | map(select(.name == $me)) | first) as $h
      | if $h == null then "say\tnone of this node's disks are in Ceph (no OSDs yet, or all out)"
        else
          [$h.children | sort[] | $osds[tostring] | select(.kb > 0)] as $mine
          | ($h.kb_used / $h.kb) as $now
          | ($mine[]
              | (.kb_used / .kb) as $u
              | "say\t\(.name): \(.kb_used | gib) of \(.kb | gib) GiB used (\($u | pc)%)",
                (select($u >= $near) | "FAIL\tCeph disk \(.name) is \($u | pc)% full (recovery stops at \($dump.backfillfull_ratio | pc)%, every write at \($dump.full_ratio | pc)%) -- free space or add disks")),
            "say\tthis node: \($h.kb_used | gib) of \($h.kb | gib) GiB (\($now | pc)%); the cluster: \($tree.summary.total_kb_used | gib) of \($tree.summary.total_kb | gib) GiB (\($tree.summary.total_kb_used / $tree.summary.total_kb | pc)%); \($limits)",
            (if ($mine | length) > 1 then
               ($h.kb - ($mine | map(.kb) | max)) as $left
               | ($h.kb_used / $left) as $after
               | ($near * $left / $h.kb * 100 | floor) as $keep
               | (if ($mine | length) == 2 then "the other" else "the others" end) as $rest
               | "say\tif one of its disks failed: \($rest) \($after | fill) (a disk failure fits while the node stays under \($keep)%)",
                 (select($after >= $near) | "WARN\tif one of this node's Ceph disks failed, its data would leave \($rest) \($after | fill) (Ceph warns at \($near | pc)%) -- keep the node under \($keep)% (now \($now | pc)%): free space or add disks")
             else "say\tonly one disk of this node is in: if it failed, nothing would move onto another of its disks" end),
            ([$pgs.pg_stats[] | {b: (.stat_sum.num_bytes / 1024), pool: $poolName[.pgid | split(".")[0]],
                                 hosts: ([.up[] | $hostOf[tostring] // empty] | unique)}] as $pg
             | $hosts[] | select(.name != $me) | .name as $g
             # each copy lost with $g is re-made on a node that has none of that PG yet
             | [$pg[] | select(any(.hosts[]; . == $g) and all(.hosts[]; . != $me))
                      | .b /= ([$hosts[].name] - .hosts | length)] as $moved
             | ($moved | map(.b) | add // 0) as $gain
             | (($h.kb_used + $gain) / $h.kb) as $after
             | ($moved | map(select(.b > 0) | .pool) | unique | join(", ")) as $pools
             | "say\tif \($g) failed: about \($gain | gib) GiB more here\(if $pools != "" then " (its copies of \($pools))" else "" end), \($after | fill)",
               (select($gain > 0 and $after >= $near) | "WARN\tif \($g) failed, re-making its copies of \($pools) (about \($gain | gib) GiB) would leave this node's Ceph disks \($after | fill) (Ceph warns at \($near | pc)%) -- free space or add disks"))
        end
    '';

    hwcheck = pkgs.writeShellApplication {
      name = "cluster-hwcheck";
      runtimeInputs = with pkgs; [
        smartmontools lm_sensors jq coreutils gawk gnugrep util-linux config.systemd.package chrony ceph
      ];
      text = /* bash */ ''
        REPORT=${report}
        SPACE=${space}
        RING_LINKS=${lib.escapeShellArg (lib.concatStringsSep " " config.var.cluster.host.ring)}
        HOST=${config.networking.hostName}

        # cluster-hwcheck -- hardware health report for one node, run as root by
        # cluster-hwcheck.timer (see health.nix). Writes REPORT, readable by group
        # cluster-read, so `cluster debug` can show it without root.
        #
        # First lines are a verdict and an attention list; details follow. A check
        # whose hardware isn't present (VMs have no SMART or sensors) says so instead
        # of passing silently.
        #
        # Set by health.nix: REPORT (output path), SPACE (the disk-space lines of
        # the attention list, empty when none), RING_LINKS (space-separated),
        # HOST (this node's name, also its CRUSH host)

        status=OK
        attention=()
        space=()
        details=$(mktemp)
        trap 'rm -f "$details"' EXIT

        flag() {  # flag <WARN|FAIL> <message>
          attention+=("$1  $2")
          if [ "$1" = FAIL ]; then status=FAIL
          elif [ "$status" = OK ]; then status=WARN; fi
        }
        space_flag() { flag "$1" "$2"; space+=("$1  $2"); }  # ...about disk space
        sec() { printf '\n--- %s\n' "$1" >>"$details"; }
        say() { printf '%s\n' "$*" >>"$details"; }
        num() { [[ "''${1:-}" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }
        # exists <glob...>: true if the glob matched a path (an unmatched glob stays
        # literal and fails -e). Not compgen -G: the non-interactive bash these
        # scripts run under has no programmable completion, so compgen is missing.
        exists() { for p in "$@"; do [ -e "$p" ] && return 0; done; return 1; }

        # ------------------------------------------------------------- disks (SMART)
        sec "Disks (SMART)"
        while read -r dev _ type _; do
          [ -n "$dev" ] || continue
          j=$(smartctl -j -a "$dev" -d "$type" 2>/dev/null || true)  # nonzero exit is a bitmask of findings
          model=$(jq -r '.model_name // .scsi_model_name // .product // "unknown"' <<<"$j" 2>/dev/null || echo unknown)
          passed=$(jq -r 'if .smart_status == null then "n/a" else (.smart_status.passed|tostring) end' <<<"$j" 2>/dev/null || echo n/a)
          temp=$(num "$(jq -r '.temperature.current // 0' <<<"$j" 2>/dev/null)")
          line="$dev ($model): health=$passed temp=''${temp}C"

          if [ "$passed" = n/a ]; then
            say "$line -- SMART not available (virtual disk?)"
            continue
          fi
          [ "$passed" = false ] && flag FAIL "$dev ($model): SMART overall health check FAILED -- replace it"

          if [ "$(jq -r '.nvme_smart_health_information_log != null' <<<"$j")" = true ]; then
            read -r cw used media errlog < <(jq -r '.nvme_smart_health_information_log | "\(.critical_warning // 0) \(.percentage_used // 0) \(.media_errors // 0) \(.num_err_log_entries // 0)"' <<<"$j")
            line+=" wear=''${used}% media_errors=$media error_log=$errlog critical_warning=$cw"
            [ "$(num "$cw")" -ne 0 ] && flag FAIL "$dev ($model): NVMe critical warning $cw"
            [ "$(num "$media")" -gt 0 ] && flag WARN "$dev ($model): $media media errors"
            [ "$(num "$used")" -ge 80 ] && flag WARN "$dev ($model): ''${used}% of rated wear used"
            [ "$temp" -ge 70 ] && flag WARN "$dev ($model): ''${temp}C"
          else
            # ATA: 5 reallocated, 187 reported uncorrectable, 197 pending,
            # 198 offline uncorrectable, 199 CRC errors (cable/connector)
            while read -r id name raw; do
              line+=" $name=$raw"
              if [ "$(num "$raw")" -gt 0 ]; then
                case $id in
                  199) flag WARN "$dev ($model): $raw CRC errors -- check the cable/connector" ;;
                  *)   flag WARN "$dev ($model): $name = $raw" ;;
                esac
              fi
            done < <(jq -r '.ata_smart_attributes.table[]? | select(.id == 5 or .id == 187 or .id == 197 or .id == 198 or .id == 199) | "\(.id) \(.name) \(.raw.value)"' <<<"$j")
            [ "$temp" -ge 55 ] && flag WARN "$dev ($model): ''${temp}C"
          fi
          say "$line"
        done < <(smartctl --scan 2>/dev/null)

        # ------------------------------------------------------- temperatures, fans
        sec "Temperatures and fans"
        readings=$(sensors -j 2>/dev/null | jq -r '
          to_entries[] | .key as $chip | .value | to_entries[]
          | select(.value | type == "object") | .key as $feat | .value as $v
          | $v | keys[] | select(test("^(temp|fan)[0-9]+_input$")) as $k
          | "\($chip)|\($feat)|\($k)|\($v[$k])|\($v[$k | sub("_input"; "_crit")] // $v[$k | sub("_input"; "_max")] // "")"
        ' 2>/dev/null || true)
        if [ -z "$readings" ]; then
          say "no hardware sensors visible (VM, or lm_sensors has no driver for this board)"
        else
          while IFS='|' read -r chip feat key val limit; do
            v=''${val%.*}; l=''${limit%.*}
            case $key in
              temp*)
                say "$chip $feat: ''${v}C''${l:+ (limit ''${l}C)}"
                if { [ -n "$l" ] && [ "$(num "$l")" -gt 0 ] && [ "$(num "$v")" -ge "$(num "$l")" ]; } || [ "$(num "$v")" -ge 90 ]; then
                  flag WARN "$chip $feat at ''${v}C''${l:+ (limit ''${l}C)}"
                fi ;;
              fan*)
                say "$chip $feat: ''${v} RPM"
                [ "$(num "$v")" -eq 0 ] && flag WARN "$chip $feat reads 0 RPM -- fan stopped or unplugged" ;;
            esac
          done <<<"$readings"
        fi

        # ------------------------------------------------------------ CPU throttling
        sec "CPU thermal throttling (since boot)"
        if exists /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count; then
          pkg=$(cat /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count | sort -n | tail -1)
          core=$(cat /sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count | awk '{s+=$1} END {print s+0}')
          say "package events: $pkg, core events (all cores): $core"
          [ "$(num "$pkg")" -gt 0 ] && flag WARN "CPU package thermal throttling: $pkg events since boot -- check cooling"
        else
          say "not available (VM)"
        fi

        # ------------------------------------------------------------- memory errors
        sec "Memory errors (EDAC)"
        if exists /sys/devices/system/edac/mc/mc*; then
          for mc in /sys/devices/system/edac/mc/mc*; do
            ce=$(cat "$mc/ce_count" 2>/dev/null || echo 0); ue=$(cat "$mc/ue_count" 2>/dev/null || echo 0)
            say "''${mc##*/}: corrected=$ce uncorrected=$ue"
            [ "$(num "$ue")" -gt 0 ] && flag FAIL "''${mc##*/}: $ue uncorrected memory errors"
            [ "$(num "$ce")" -gt 0 ] && flag WARN "''${mc##*/}: $ce corrected memory errors"
          done
        else
          say "no EDAC memory controller (non-ECC RAM or VM)"
        fi

        # ---------------------------------------------------- kernel hardware errors
        sec "Kernel hardware errors (this boot)"
        hw=$(journalctl -k -b -p warning --no-pager -o short-monotonic 2>/dev/null \
          | grep -E 'I/O error|Buffer I/O|blk_update_request|Medium Error|critical medium|nvme.*(timeout|reset|abort|error)|Hardware Error|mce:|EDAC|ata[0-9.]+: (exception|failed|hard resetting)|thunderbolt.*(fail|error|timeout)|PCIe Bus Error|AER' \
          | grep -vE 'dev (rbd|loop|nbd)[0-9]|rbd[0-9]+: ' || true)
        if [ -n "$hw" ]; then
          n=$(wc -l <<<"$hw")
          flag WARN "$n kernel hardware error lines this boot (first: $(head -1 <<<"$hw" | cut -c1-140))"
          head -20 <<<"$hw" >>"$details"
        else
          say "none"
        fi

        sec "Out-of-memory kills (this boot)"
        oom=$(journalctl -k -b --no-pager -o cat 2>/dev/null | grep -cE 'Out of memory|oom-kill' || true)
        say "$oom"
        [ "$(num "$oom")" -gt 0 ] && flag WARN "$oom out-of-memory kills this boot"

        # --------------------------------------------------------------- disk space
        sec "Disk space"
        # One line per filesystem: /nix, /persistent and /var/log share the
        # boot disk's btrfs. / is RAM (tmpfs), /boot holds the kernels.
        fs=(); declare -A mounts=() usage=()
        while read -r src size used pct target; do
          key=$src; [[ $src == /dev/* ]] || key=$target
          if [ -z "''${mounts[$key]:-}" ]; then
            fs+=("$key"); mounts[$key]=$target; usage[$key]="$used $size $pct"
          else mounts[$key]+=", $target"; fi
        done < <(df -h --output=source,size,used,pcent,target / /boot /nix /persistent /var/log 2>/dev/null | tail -n +2)
        for key in "''${fs[@]}"; do
          read -r used size pct <<<"''${usage[$key]}"
          t=''${mounts[$key]}; p=''${pct%\%}
          say "$t: $used of $size used ($pct)"
          if [ "$(num "$p")" -ge 95 ]; then space_flag FAIL "$t: $pct full"
          elif [ "$(num "$p")" -ge 85 ]; then space_flag WARN "$t: $pct full"; fi
        done

        sec "Ceph disks (space)"
        cj() { timeout 20 ceph --id status "$@" -f json 2>/dev/null; }
        if tree=$(cj osd df tree) && dump=$(cj osd dump) && pgs=$(cj pg ls) \
           && ceph_space=$(printf '%s\n' "$tree" "$dump" "$pgs" | jq -nr --arg me "$HOST" -f ${cephSpace}); then
          while IFS=$'\t' read -r kind text; do
            if [ "$kind" = say ]; then say "$text"; else space_flag "$kind" "$text"; fi
          done <<<"$ceph_space"
        else
          say "Ceph doesn't answer (no quorum?) -- cluster debug's cluster-wide part says why"
        fi

        sec "Memory"
        avail=$(awk '/MemAvailable/ {a=$2} /MemTotal/ {t=$2} END {printf "%d", a*100/t}' /proc/meminfo)
        say "available: ''${avail}%"
        [ "$avail" -lt 10 ] && flag WARN "only ''${avail}% memory available"

        # ---------------------------------------------------------------- ring links
        sec "Ring links"
        for l in ''${RING_LINKS:-}; do
          d=/sys/class/net/$l
          [ -d "$d" ] || { flag WARN "ring link $l doesn't exist"; continue; }
          carrier=$(cat "$d/carrier" 2>/dev/null || echo 0)
          changes=$(cat "$d/carrier_changes" 2>/dev/null || echo 0)
          rxe=$(cat "$d/statistics/rx_errors"); txe=$(cat "$d/statistics/tx_errors")
          say "$l: carrier=$carrier carrier_changes=$changes rx_errors=$rxe tx_errors=$txe"
          [ "$carrier" = 1 ] || flag WARN "ring link $l is down"
          [ "$(num "$changes")" -gt 20 ] && flag WARN "ring link $l has flapped ($changes carrier changes since boot)"
          [ "$(( $(num "$rxe") + $(num "$txe") ))" -gt 0 ] && flag WARN "ring link $l: $rxe rx / $txe tx errors"
        done

        # ----------------------------------------------------------- last shutdown
        sec "Previous shutdown"
        if journalctl --list-boots --no-pager 2>/dev/null | awk '$1 == -1 {found=1} END {exit !found}'; then
          if journalctl -b -1 --no-pager -o cat -n 40 2>/dev/null | grep -qE 'Journal stopped|Reached target .*(Power-Off|Reboot|Shutdown)|systemd-shutdown'; then
            say "clean"
          else
            say "no clean shutdown recorded"
            flag WARN "the previous boot ended without a clean shutdown (power cut, crash or hard reset)"
          fi
        else
          say "no previous boot recorded"
        fi

        # ---------------------------------------------------- kernel crash records
        sec "Kernel crash records (pstore)"
        crashes=$(find /var/lib/systemd/pstore -type f 2>/dev/null | wc -l)
        if [ "$crashes" -gt 0 ]; then
          latest=$(find /var/lib/systemd/pstore -type f -printf '%TY-%Tm-%Td %TH:%TM %p\n' | sort | tail -1)
          say "$crashes files, latest: $latest"
          flag WARN "kernel crash record(s) saved from a previous boot (latest $latest) -- read with: sudo ls -R /var/lib/systemd/pstore, then delete them to clear this"
        else
          say "none"
        fi

        # --------------------------------------------------------------------- clock
        sec "Clock"
        off=$(chronyc -c tracking 2>/dev/null | cut -d, -f5 || true)
        if [ -n "$off" ]; then
          say "offset ''${off}s"
          awk -v o="$off" 'BEGIN { if (o < 0) o = -o; exit !(o > 0.05) }' && flag WARN "clock off by ''${off}s (Ceph mons tolerate 0.05s)"
        else
          say "chrony not answering"
          flag WARN "chrony not answering"
        fi

        # -------------------------------------------------------------------- write
        {
          echo "STATUS: $status"
          echo "CHECKED: $(date -u '+%FT%TZ')"
          echo "ATTENTION:"
          if [ ''${#attention[@]} -eq 0 ]; then echo "  none"; else printf '  %s\n' "''${attention[@]}"; fi
          cat "$details"
        } >"$REPORT.tmp"
        mv "$REPORT.tmp" "$REPORT"
        if [ ''${#space[@]} -eq 0 ]; then : >"$SPACE.tmp"; else printf '%s\n' "''${space[@]}" >"$SPACE.tmp"; fi
        mv "$SPACE.tmp" "$SPACE"
      '';
    };
  in {
    environment.systemPackages = [ hwcheck pkgs.lm_sensors ];

    systemd.tmpfiles.rules = [ "d /run/cluster-health 0750 root cluster-read - -" ];

    systemd.services.cluster-hwcheck = {
      description = "Hardware health check for cluster debug";
      after = [ "chronyd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe hwcheck;
        ExecStartPost = "${pkgs.coreutils}/bin/chgrp cluster-read ${report} ${space}";
        UMask = "0027";
        Nice = 10;
      };
    };

    systemd.timers.cluster-hwcheck = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "15min";
      };
    };
  };
}
