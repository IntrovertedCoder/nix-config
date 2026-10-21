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
      # rados comes from the node's own system (its Ceph version).
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
        cookie="$(hostname)-$$"

        if ! "''${R[@]}" lock get lock tofu --lock-cookie "$cookie" --lock-duration 7200 \
             --lock-description "$(hostname) $(date -u +%FT%TZ): tofu $*" 2>/dev/null; then
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
          "''${R[@]}" ls | grep -E "^$STATE\.[0-9]+$" | sort -t. -k3 -n | head -n -20 \
            | while read -r old; do "''${R[@]}" rm "$old"; done
        }

        finish() {
          local rc=$?
          if ! save; then
            echo "SAVING THE STATE TO CEPH FAILED -- it's in $W/$STATE on $(hostname); put it back by hand:" >&2
            echo "  rados -p important -N opentofu put $STATE $W/$STATE" >&2
            release; exit 1
          fi
          rm -f "$STATE" "$STATE.orig" "$STATE.backup"
          release
          exit "$rc"
        }
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
        tofu "$@"
      '';
    };
  in lib.mkIf pkgs.stdenv.isLinux {
    devShells.default = pkgs.mkShell { packages = [ tofu ]; };

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
        # image to the node, sends the .tf files and the values from the flake
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

        # ---- values from the flake, so nothing is typed twice
        # The controller's image (modules/cluster/unifi.nix). Same flake, same
        # store paths: OpenTofu only replaces the image (and so the instance)
        # when the system actually changed.
        meta=$(nix build --no-link --print-out-paths .#nixosConfigurations.unifi.config.system.build.metadata)
        data=$(nix build --no-link --print-out-paths .#nixosConfigurations.unifi.config.system.build.squashfs)
        # The cluster's plan (opentofu/cluster.tf): members and their node ids,
        # the transit VLAN and ring MTU (same on every node), and the subnets.
        members=$(i=0; for n in "''${NODES[@]}"; do i=$((i + 1)); echo "$(name "$n") $i"; done \
          | jq -Rn '[inputs | split(" ") | {(.[0]): (.[1] | tonumber)}] | add')
        host=$(nix eval --json ".#nixosConfigurations.$(name "''${NODES[0]}").config.var.cluster.host" \
          --apply 'h: { transit_vlan = h.vlans.transit; ring_mtu = h.ringMtu; }')
        lan=$(nix eval --json --impure --expr 'let l = import ./modules/cluster/_lan.nix; in
          { transit = { inherit (l.segments.transit) v4 v6; }; inherit (l) services ovnUplink; }')
        mkdir "$_TMP/up"
        cp opentofu/*.tf "$_TMP/up/"
        jq -n --arg m "$(echo "$meta"/tarball/*.tar.xz)" --arg d "$(echo "$data"/*.squashfs)" \
          --argjson members "$members" --argjson host "$host" --argjson lan "$lan" \
          '{unifi_image: {metadata: $m, data: $d},
            cluster: ($host + {members: $members, lan: $lan})}' > "$_TMP/up/flake.auto.tfvars.json"

        # ---- to the node: the runner (OpenTofu and the provider) and the
        # image, then this checkout's files
        NIX_SSHOPTS="''${SSH_OPTS[*]}" nix copy --no-check-sigs --to "ssh-ng://root@$(ip "$node")" \
          ${runner} "$meta" "$data"
        W=/var/lib/elements-tofu
        tar -C "$_TMP/up" -cf - . | on "$node" \
          "mkdir -p $W && find $W -maxdepth 1 \( -name '*.tf' -o -name '*.tfvars.json' \) -delete && tar -C $W -xf -"

        echo "== OpenTofu on $(name "$node")"
        tty=(); [ -t 0 ] && tty=(-t)
        # shellcheck disable=SC2029  # meant to expand here: the arguments, quoted
        ssh "''${SSH_OPTS[@]}" "''${tty[@]}" "root@$(ip "$node")" \
          "${runner}/bin/elements-tofu-run $W $(printf '%q ' "$@")"
      '';
    };
  };
}
