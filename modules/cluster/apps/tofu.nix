{ ... }: {
  perSystem = { pkgs, lib, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
    # The provider from nixpkgs, pinned by flake.lock: no registry download.
    tofu = pkgs.opentofu.withPlugins (p: [ p.lxc_incus ]);
  in lib.mkIf pkgs.stdenv.isLinux {
    devShells.default = pkgs.mkShell { packages = [ tofu ]; };

    packages.tofu = cluster.mkApp {
      name = "tofu";
      runtimeInputs = [ tofu pkgs.openssl pkgs.jq pkgs.iproute2 ];
      text = /* bash */ ''
        # OpenTofu for the cluster's Incus objects (opentofu/ in this repo):
        #
        #   nix run .#tofu -- plan
        #   nix run .#tofu -- apply
        #
        # Incus's API only listens on the mesh addresses, so this forwards a
        # local port over SSH (as shot, port 20530) through the first node that
        # answers, to that node's mesh address -- what node.nix's PermitOpen
        # allows. No listener anywhere else. The client certificate lives in
        # ~/.config/elements-tofu; the first run makes it and adds it to the
        # cluster's trust store over SSH. OpenTofu pins the cluster's own
        # certificate there on first use.

        CONF=''${ELEMENTS_TOFU_CONFIG:-$HOME/.config/elements-tofu}

        # ---- client certificate, trusted by the cluster
        if [ ! -s "$CONF/client.crt" ]; then
          mkdir -p "$CONF"; chmod 700 "$CONF"
          ( umask 077
            openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 -nodes -days 3650 \
              -subj "/CN=tofu@$(hostname)" -keyout "$CONF/client.key" -out "$CONF/client.crt" 2>/dev/null )
          echo "== made a client certificate in $CONF"
        fi
        fp=$(openssl x509 -in "$CONF/client.crt" -outform der | sha256sum | cut -d' ' -f1)

        node=""; id=0; i=0
        for n in "''${NODES[@]}"; do
          i=$((i + 1))
          if on "$n" true 2>/dev/null; then node=$n; id=$i; break; fi
        done
        [ -n "$node" ] || { echo "no node answers over SSH" >&2; exit 1; }

        if ! on "$node" "incus config trust show $fp" </dev/null >/dev/null 2>&1; then
          echo "== adding this machine's client certificate to the cluster's trust store"
          # shellcheck disable=SC2016  # $f expands on the node, not here
          on "$node" 'f=$(mktemp); cat > "$f"; incus config trust add-certificate "$f" --name "tofu-'"$(hostname)"'"; rm -f "$f"' < "$CONF/client.crt"
        fi

        # ---- tunnel to that node's Incus API on the mesh
        # A fixed local port: the address is a variable, and a saved plan
        # (plan -out, then apply <plan>) only applies with the same values.
        port=''${ELEMENTS_TOFU_PORT:-18443}
        if ss -Htln "sport = :$port" | grep -q .; then
          echo "local port $port is in use (another tofu run?); set ELEMENTS_TOFU_PORT" >&2; exit 1
        fi
        ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=8 -o "UserKnownHostsFile=$KNOWN_HOSTS" \
            -o StrictHostKeyChecking=yes -o LogLevel=ERROR -o ExitOnForwardFailure=yes \
            -f -N -M -S "$_TMP/tunnel-tofu" -L "$port:[fd9a:7af:74af:ff::$id]:8443" -p 20530 "shot@$(ip "$node")" \
          || { echo "couldn't open the tunnel to $(name "$node")'s Incus API" >&2; exit 1; }

        export TF_VAR_incus_address="https://127.0.0.1:$port"
        export TF_VAR_incus_config_dir="$CONF"

        # ---- values from the flake, so nothing is typed twice
        # The controller's image (modules/cluster/unifi.nix). Same flake, same
        # store paths: OpenTofu only replaces the image (and so the instance)
        # when the system actually changed.
        meta=$(nix build --no-link --print-out-paths .#nixosConfigurations.unifi.config.system.build.metadata)
        data=$(nix build --no-link --print-out-paths .#nixosConfigurations.unifi.config.system.build.squashfs)
        jq -n --arg m "$(echo "$meta"/tarball/*.tar.xz)" --arg d "$(echo "$data"/*.squashfs)" \
          '{unifi_image: {metadata: $m, data: $d}}' > opentofu/flake.auto.tfvars.json

        [ -d opentofu/.terraform ] || tofu -chdir=opentofu init -input=false >/dev/null
        tofu -chdir=opentofu "$@"
      '';
    };
  };
}
