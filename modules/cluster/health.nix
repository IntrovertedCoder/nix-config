{ lib, ... }: {
  # Hardware health check on every cluster node: SMART, temperatures, fans,
  # throttling, memory errors, kernel hardware errors, disk space, ring links,
  # unclean shutdowns, kernel crash records, clock. Runs as root (SMART needs
  # it) every 15 minutes and writes /run/cluster-health/report.txt for group
  # wheel, which is what `cluster debug` reads -- so the tool itself never
  # needs root. (Bash `${...}` is written `''${...}` inside the Nix string.)
  flake.nixosModules.clusterHealth = { config, lib, pkgs, ... }: let
    report = "/run/cluster-health/report.txt";
    hwcheck = pkgs.writeShellApplication {
      name = "cluster-hwcheck";
      runtimeInputs = with pkgs; [
        smartmontools lm_sensors jq coreutils gawk gnugrep util-linux config.systemd.package chrony
      ];
      text = ''
        REPORT=${report}
        RING_LINKS=${lib.escapeShellArg (lib.concatStringsSep " " config.var.cluster.host.ring)}

        # cluster-hwcheck -- hardware health report for one node, run as root by
        # cluster-hwcheck.timer (see health.nix). Writes REPORT, readable by group
        # wheel, so `cluster debug` can show it without root.
        #
        # First lines are a verdict and an attention list; details follow. A check
        # whose hardware isn't present (VMs have no SMART or sensors) says so instead
        # of passing silently.
        #
        # Set by health.nix: REPORT (output path), RING_LINKS (space-separated)

        status=OK
        attention=()
        details=$(mktemp)
        trap 'rm -f "$details"' EXIT

        flag() {  # flag <WARN|FAIL> <message>
          attention+=("$1  $2")
          if [ "$1" = FAIL ]; then status=FAIL
          elif [ "$status" = OK ]; then status=WARN; fi
        }
        sec() { printf '\n--- %s\n' "$1" >>"$details"; }
        say() { printf '%s\n' "$*" >>"$details"; }
        num() { [[ "''${1:-}" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }

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
        if compgen -G '/sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count' >/dev/null; then
          pkg=$(cat /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_count | sort -n | tail -1)
          core=$(cat /sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count | awk '{s+=$1} END {print s+0}')
          say "package events: $pkg, core events (all cores): $core"
          [ "$(num "$pkg")" -gt 0 ] && flag WARN "CPU package thermal throttling: $pkg events since boot -- check cooling"
        else
          say "not available (VM)"
        fi

        # ------------------------------------------------------------- memory errors
        sec "Memory errors (EDAC)"
        if compgen -G '/sys/devices/system/edac/mc/mc*' >/dev/null; then
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
        while read -r target pct; do
          p=''${pct%\%}
          say "$target ''${pct} used"
          if [ "$(num "$p")" -ge 95 ]; then flag FAIL "$target is ''${pct} full"
          elif [ "$(num "$p")" -ge 85 ]; then flag WARN "$target is ''${pct} full"; fi
        done < <(df --output=target,pcent / /nix /persistent /var/log 2>/dev/null | tail -n +2)

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
      '';
    };
  in {
    environment.systemPackages = [ hwcheck pkgs.lm_sensors ];

    systemd.tmpfiles.rules = [ "d /run/cluster-health 0750 root wheel - -" ];

    systemd.services.cluster-hwcheck = {
      description = "Hardware health check for cluster debug";
      after = [ "chronyd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe hwcheck;
        ExecStartPost = "${pkgs.coreutils}/bin/chgrp wheel ${report}";
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
