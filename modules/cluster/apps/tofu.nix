{ ... }: {
  perSystem = { pkgs, lib, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
    # The provider from nixpkgs, pinned by flake.lock: no registry download.
    tofu = pkgs.opentofu.withPlugins (p: [ p.lxc_incus ]);

    # The half that runs on a node, as root: OpenTofu against that node's
    # Incus socket, the state kept in Ceph. The app below copies it there.
    runner = pkgs.writeShellApplication {
      name = "elements-tofu-run";
      runtimeInputs = [ tofu pkgs.jq pkgs.coreutils pkgs.gnugrep ];
      # rados and incus come from the node's own system (its versions).
      text = /* bash */ ''
        #   elements-tofu-run <workdir> <tofu arguments...>
        #
        # The state is one object in the `important` pool (3 copies), in its
        # own namespace: `terraform.tfstate`, plus the previous ones as
        # `terraform.tfstate.<serial>` (the last 20). One run at a time, any
        # node: a Ceph lock on the `lock` object, which expires by itself
        # after 2 hours if a run dies without releasing it.
        W=$1; shift
        cd "$W"
        R=(rados -p important -N opentofu)
        STATE=terraform.tfstate
        cookie="$(uname -n)-$$"

        if ! "''${R[@]}" lock get lock tofu --lock-cookie "$cookie" --lock-duration 7200 \
             --lock-description "$(uname -n) $(date -u +%FT%TZ): tofu $*" 2>/dev/null; then
          echo "another OpenTofu run holds the lock:" >&2
          "''${R[@]}" lock info lock tofu >&2 || true
          echo >&2
          echo "It expires 2 hours after it was taken. If that run is gone, break it on a node:" >&2
          echo "  rados -p important -N opentofu lock break lock tofu <name> --lock-cookie <cookie>" >&2
          exit 1
        fi

        release() {
          local locker
          locker=$("''${R[@]}" lock info lock tofu --format=json \
            | jq -r --arg c "$cookie" '.lockers[] | select(.cookie == $c) | .name') || true
          [ -z "$locker" ] || "''${R[@]}" lock break lock tofu "$locker" --lock-cookie "$cookie" || true
        }

        # Back to Ceph if the run changed it: the old one kept by its serial
        # first, then the new one.
        save() {
          [ -f "$STATE" ] || return 0
          [ "$(sha256sum < "$STATE")" != "$before" ] || return 0
          if [ -f "$STATE.orig" ]; then
            "''${R[@]}" put "$STATE.$(jq .serial "$STATE.orig")" "$STATE.orig" || return 1
          fi
          "''${R[@]}" put "$STATE" "$STATE" || return 1
          echo "== state saved to Ceph (serial $(jq .serial "$STATE"))"
          # (No old copies yet, on a new cluster, isn't a failure.)
          { "''${R[@]}" ls | grep -E "^$STATE\.[0-9]+$" || true; } | sort -t. -k3 -n | head -n -20 \
            | while read -r old; do "''${R[@]}" rm "$old"; done
        }

        finish() {
          local rc=$?
          if ! save; then
            echo "SAVING THE STATE TO CEPH FAILED -- it's in $W/$STATE on $(uname -n); put it back by hand:" >&2
            echo "  rados -p important -N opentofu put $STATE $W/$STATE" >&2
            release; exit 1
          fi
          rm -f "$STATE" "$STATE.orig" "$STATE.backup"
          release
          exit "$rc"
        }
        # A state file here means a run never finished: the node went down
        # before finish() could save it (the work directories are kept on
        # disk for this). The same as Ceph's: nothing was lost (a plan, or an
        # apply that changed nothing). Different: an apply changed things
        # after the last save, and this one is the truth -- never delete it.
        if [ -f "$STATE" ]; then
          if "''${R[@]}" get "$STATE" "$STATE.ceph" 2>/dev/null && cmp -s "$STATE" "$STATE.ceph"; then
            echo "== a run here didn't finish; its state is the same as Ceph's: going on"
            rm -f "$STATE.ceph"
          else
            echo "A run here didn't finish, and its state ($W/$STATE, serial $(jq .serial "$STATE"))" >&2
            echo "differs from Ceph's (serial $(jq .serial "$STATE.ceph" 2>/dev/null || echo none)): an apply changed things after the last save." >&2
            echo "If this one is newer, put it in Ceph, then remove it here and run again:" >&2
            echo "  rados -p important -N opentofu put $STATE $W/$STATE && rm $W/$STATE" >&2
            rm -f "$STATE.ceph"; release; exit 1
          fi
        fi

        trap finish EXIT
        # Wait for tofu to finish (bash runs the trap after the foreground
        # command), then save and unlock.
        trap 'exit 129' HUP INT TERM

        rm -f "$STATE" "$STATE.orig" "$STATE.backup"
        if out=$("''${R[@]}" stat "$STATE" 2>&1); then
          "''${R[@]}" get "$STATE" "$STATE"
          cp "$STATE" "$STATE.orig"
          before=$(sha256sum < "$STATE")
        elif grep -q "No such file" <<<"$out"; then
          # A new cluster: nothing declared yet.
          echo "== no state in Ceph yet: starting from none"
          before=none
        else
          echo "couldn't read the state from Ceph: $out" >&2
          exit 1
        fi

        [ -d .terraform ] || tofu init -input=false >/dev/null

        # The Incus provider force-stops an instance before it deletes it: a
        # power-off for a VM, a kill for a container. So every replacement of
        # the UniFi controller or console stopped its database uncleanly (the
        # controller's MongoDB: "Detected unclean shutdown" after each
        # Monday's update). An apply first stops, cleanly, every instance the
        # plan deletes or replaces; the provider leaves a stopped one alone.
        # That needs the plan before the apply, so a plain `apply` plans into
        # a file, asks as OpenTofu would, then applies that file.
        stop_deleted() {
          local name state
          for name in $(jq -r '.resource_changes[]?
              | select(.type == "incus_instance" and (.change.actions | index("delete")))
              | .change.before.name' <<<"$1"); do
            state=$(incus list -f json </dev/null | jq -r --arg n "$name" '.[] | select(.name == $n) | .status') || state=""
            [ "$state" = Running ] || continue
            echo "== stopping $name cleanly before OpenTofu deletes it"
            incus stop "$name" --timeout 120 </dev/null \
              || echo "$name didn't stop within 120 s: OpenTofu force-stops it" >&2
          done
        }

        apply() {
          local a json auto="" opts=() out=() rc=0 answer
          # A saved plan (apply [options] <plan file>): stop, then apply it.
          if [ $# -gt 0 ] && [ -f "''${!#}" ] && json=$(tofu show -json "''${!#}" 2>/dev/null); then
            stop_deleted "$json"
            tofu apply "$@"
            return
          fi
          # The options for the plan; those about output also for the apply
          # (a saved plan takes no -target, -var and the like).
          for a in "$@"; do
            case $a in
              -auto-approve) auto=1 ;;
              -no-color|-compact-warnings|-parallelism=*) opts+=("$a"); out+=("$a") ;;
              *) opts+=("$a") ;;
            esac
          done
          tofu plan -detailed-exitcode -out=apply.tfplan "''${opts[@]}" || rc=$?
          # 0: nothing to change; 2: changes; anything else: plan failed
          if [ $rc -ne 2 ]; then rm -f apply.tfplan; return $rc; fi
          if [ -z "$auto" ]; then
            printf '\nDo you want to perform these actions?\n  Only "yes" will be accepted to approve.\n\n  Enter a value: '
            read -r answer || answer=""
            if [ "$answer" != yes ]; then printf '\nApply cancelled.\n'; rm -f apply.tfplan; return 1; fi
          fi
          rc=0
          stop_deleted "$(tofu show -json apply.tfplan)"
          tofu apply "''${out[@]}" apply.tfplan || rc=$?
          rm -f apply.tfplan
          return $rc
        }

        if [ "''${1:-}" = apply ]; then
          shift
          apply "$@"
        else
          tofu "$@"
        fi
      '';
    };

    # The work directory for the runner, from a checkout of this repo: the
    # .tf files, and the values from the flake, so nothing is typed twice.
    # Used by the app below (on the workstation) and by cluster-update (on
    # a node, from its own checkout). Prints the store paths of the UniFi
    # OS console's image, which the runner's node needs.
    #
    #   elements-tofu-prepare <checkout> <workdir> [nix build options...]
    #
    # FLAKE overrides the flake reference for the builds (default: the
    # checkout), e.g. git+file://<checkout>?shallow=1 for a shallow clone.
    prepare = pkgs.writeShellApplication {
      name = "elements-tofu-prepare";
      runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.findutils ];
      # nix comes from the caller's system (its daemon's version).
      text = /* bash */ ''
        src=$1 dest=$2; shift 2
        flake=''${FLAKE:-$src}
        # The UniFi OS console's VM image (modules/cluster/unifi-os.nix). Same
        # flake, same store paths: OpenTofu only replaces the image (and so
        # the instance) when the system actually changed.
        osMeta=$(nix build --no-link --print-out-paths "$@" "$flake#nixosConfigurations.unifi-os.config.system.build.metadata")
        osData=$(nix build --no-link --print-out-paths "$@" "$flake#nixosConfigurations.unifi-os.config.system.build.qemuImage")
        # The cluster's plan (opentofu/cluster.tf): members and their node ids,
        # the transit VLAN and ring MTU (same on every node), and the subnets.
        values=$(nix eval --json --impure --expr "let
            hosts = import $src/modules/cluster/_hosts.nix;
            l = import $src/modules/cluster/_lan.nix;
            h = builtins.head (builtins.attrValues hosts);
          in {
            members = builtins.mapAttrs (_: h: h.id) hosts;
            transit_vlan = h.vlans.transit;
            ring_mtu = h.ringMtu;
            lan = { transit = { inherit (l.segments.transit) v4 v6; }; inherit (l) services ovnUplink; };
          }")
        mkdir -p "$dest"
        find "$dest" -maxdepth 1 \( -name '*.tf' -o -name '*.tfvars.json' \) -delete
        cp "$src"/opentofu/*.tf "$dest/"
        jq -n --arg om "$(echo "$osMeta"/tarball/*.tar.xz)" --arg od "$osData/nixos.qcow2" \
          --argjson c "$values" \
          '{unifi_os_image: {metadata: $om, data: $od}, cluster: $c}' \
          > "$dest/flake.auto.tfvars.json"
        printf '%s\n' "$osMeta" "$osData"
      '';
    };
  in lib.mkIf pkgs.stdenv.isLinux {
    devShells.default = pkgs.mkShell { packages = [ tofu ]; };

    # For cluster-update (modules/cluster/update.nix), on the nodes.
    packages.elements-tofu-run = runner;
    packages.elements-tofu-prepare = prepare;

    packages.tofu = cluster.mkApp {
      name = "tofu";
      runtimeInputs = [ pkgs.jq ];
      text = /* bash */ ''
        # OpenTofu for the cluster's Incus objects (opentofu/ in this repo):
        #
        #   nix run .#tofu -- plan
        #   nix run .#tofu -- apply
        #
        # It runs on the first node that answers, as root, against that node's
        # Incus socket: no API listener, no client certificate. The state is
        # in Ceph, so any node can run it and no workstation holds anything
        # (elements-tofu-run above). This copies the runner and the UniFi
        # images to the node, sends the .tf files and the values from the flake
        # to /var/lib/elements-tofu there, and runs it. A saved plan
        # (plan -out=<file>) stays in that directory, on that node.

        if [ -e opentofu/terraform.tfstate ]; then
          echo "opentofu/terraform.tfstate: the state lives in Ceph now; move this local copy away" >&2
          exit 1
        fi

        node=""
        for n in "''${NODES[@]}"; do
          if on "$n" true 2>/dev/null; then node=$n; break; fi
        done
        [ -n "$node" ] || { echo "no node answers over SSH" >&2; exit 1; }

        # ---- the .tf files and the values from this checkout's flake
        mapfile -t images < <(${lib.getExe prepare} "$PWD" "$_TMP/up")

        # ---- to the node: the runner (OpenTofu and the provider) and the
        # images, then this checkout's files. The node first takes what
        # vmtest's cache has (the images once Monday's build made them), so
        # only the rest goes over this link: 1.5 GiB of console image
        # takes minutes.
        # shellcheck disable=SC2029  # meant to expand here
        on "$node" "nix build --no-link ''${images[*]}" >/dev/null 2>&1 || true
        NIX_SSHOPTS="''${SSH_OPTS[*]}" nix copy --no-check-sigs --to "ssh-ng://root@$(ip "$node")" \
          ${runner} "''${images[@]}"
        W=/var/lib/elements-tofu
        tar -C "$_TMP/up" -cf - . | on "$node" \
          "mkdir -p $W && find $W -maxdepth 1 \( -name '*.tf' -o -name '*.tfvars.json' \) -delete && tar -C $W --no-same-owner --no-overwrite-dir -xf -"

        echo "== OpenTofu on $(name "$node")"
        tty=(); [ -t 0 ] && tty=(-t)
        # shellcheck disable=SC2029  # meant to expand here: the arguments, quoted
        ssh "''${SSH_OPTS[@]}" "''${tty[@]}" "root@$(ip "$node")" \
          "${runner}/bin/elements-tofu-run $W $(printf '%q ' "$@")"
      '';
    };
  };
}
