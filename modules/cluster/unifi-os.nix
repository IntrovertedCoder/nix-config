{ self, inputs, lib, ... }: let
  lan = import ./_lan.nix;
  infra = lan.segments.infra;
  # The console's address follows its MAC, the way the routers' ids do:
  # 02:74:af:04:00:<host> is infra .<host>. One image then serves at any of
  # these; OpenTofu's hwaddr picks the address (unifi-os.tf).
  hosts = [ 10 11 12 ];
  macFor = host: "02:74:af:04:00:${lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString host))}";
  # Which console release: data, so vmtest's Monday run can move it
  # (unifi-os-pin below, var.fleet.pins).
  pinFile = "modules/cluster/_unifi-os-pin.json";
  pin = lib.importJSON ./_unifi-os-pin.json;
in {
  # UniFi OS Server (design doc, Next: the controller's move off the Network
  # Server, whose standalone releases end with Network 10.6): an Incus VM on
  # Ceph, NixOS built from this flake like the old controller (unifi.nix).
  #
  # Ubiquiti ships the console only as an installer for Debian/Ubuntu: an
  # ELF with a zip on its end holding its programs and a podman image. Here
  # the flake unpacks that pinned download, and NixOS declares what the
  # installer would have set up -- the user, rootless podman, the sysctl,
  # the two services. Ubiquiti's own supervisor (uosserver-service) still
  # runs the console: it creates the container itself, talks to it, and
  # runs device discovery.
  #
  # The VM is disposable, like the old controller's container: its state
  # (podman's storage with the console's volumes, server.conf with the
  # console's id) lives on the unifi-os-data volume at /var/lib/uosserver.
  # An update = a new image -> OpenTofu replaces the instance, the volume
  # stays. A new console version = a new pin (_unifi-os-pin.json), which
  # vmtest moves to Ubiquiti's latest release each Monday; turn the
  # console's own automatic updates off in its settings (Control Plane,
  # Updates): they would install outside the flake, and the next VM would
  # go back to the pin's version.
  # It has no SSH: `incus exec unifi-os -- ...` from a node.
  flake.nixosConfigurations.unifi-os = inputs.nixpkgs.lib.nixosSystem {
    modules = [ self.nixosModules.unifiOsServer ];
  };

  flake.nixosModules.unifiOsServer = { config, lib, pkgs, modulesPath, ... }: let
    inherit (pin) version containerVersion;   # containerVersion: the image's tag, in the installer's image.tar
    image = "docker.io/library/uosserver:${containerVersion}";

    uos = pkgs.stdenv.mkDerivation {
      pname = "unifi-os-server";
      inherit version;
      src = pkgs.fetchurl { inherit (pin) url sha256; };
      dontUnpack = true;
      dontStrip = true;
      nativeBuildInputs = [ pkgs.unzip pkgs.autoPatchelfHook ];
      buildInputs = [ pkgs.stdenv.cc.cc.lib ];
      installPhase = ''
        # unzip warns about the installer program in front of the zip (exit 1)
        unzip -q $src -d x || [ $? -eq 1 ]
        chmod 644 x/*   # stored with no permissions at all
        tar -xOf x/image.tar manifest.json | grep -q '"uosserver:${containerVersion}"'   # the pin matches
        mkdir -p $out/bin $out/libexec $out/share
        # podman's own pasta replaces Ubiquiti's copy
        install -m755 x/uosserver-service x/updater-service x/discovery $out/libexec/
        install -m755 x/uosserver $out/bin/
        install -m755 x/purge $out/bin/uosserver-purge
        install -m644 x/portmap.json x/mounts.json $out/share/
        mv x/image.tar $out/share/
      '';
    };

    uid = 1001;
    # The supervisor hardcodes /home/uosserver (its podman config); the home
    # itself is on the data volume, linked there (as Silverblue links /home).
    home = "/home/uosserver";
    homeData = "/var/lib/uosserver/home";
    podman = config.virtualisation.podman.package;
  in {
    imports = [ "${modulesPath}/virtualisation/incus-virtual-machine.nix" ];

    nixpkgs.hostPlatform = "x86_64-linux";
    networking.hostName = "unifi-os";
    system.stateVersion = "26.05";

    networking.useNetworkd = true;
    networking.useDHCP = false;
    systemd.network.networks = lib.listToAttrs (map (host: lib.nameValuePair "10-infra-${toString host}" {
      matchConfig.MACAddress = macFor host;
      address = [ "${infra.v4}.${toString host}/${toString infra.plen}" ];
      gateway = [ "${infra.v4}.1" ];
      dns = [ "${infra.v4}.1" ];
      networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
    }) hosts);

    # The console's state. Blank on a fresh cluster: formatted on first boot.
    fileSystems."/var/lib/uosserver" = {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_data";
      fsType = "ext4";
      autoFormat = true;
      options = [ "noatime" ];
    };

    # As the installer sets them up. The data outlives each VM, so the ids
    # are pinned: the volumes' files belong to uosserver's subordinate ids.
    users.users.uosserver = {
      isNormalUser = true;
      inherit uid home;
      group = "uosserver";
      createHome = false;   # on the data volume, mounted after activation: tmpfiles below
      linger = true;        # its user manager runs rootless podman
      subUidRanges = [ { startUid = 165536; count = 65536; } ];
      subGidRanges = [ { startGid = 165536; count = 65536; } ];
    };
    users.groups.uosserver.gid = uid;
    virtualisation.podman.enable = true;
    boot.kernel.sysctl."net.ipv4.ping_group_range" = "0 2147483647";   # "allowing raw socket execution"

    systemd.tmpfiles.rules = [
      "d /var/lib/uosserver 0755 root root -"
      "d /var/lib/uosserver/logs 0750 uosserver uosserver -"
      "d ${homeData} 0700 uosserver uosserver -"
      "d ${homeData}/tmp 0755 uosserver uosserver -"
      "d ${homeData}/.config 0755 uosserver uosserver -"
      "d ${homeData}/.config/containers 0755 uosserver uosserver -"
      "L+ ${homeData}/.config/containers/containers.conf - - - - /etc/containers/containers.conf"
      "L+ ${home} - - - - ${homeData}"
      # The supervisor calls /usr/bin/podman, with its own PATH
      "L+ /usr/bin/podman - - - - ${podman}/bin/podman"
    ];

    # The programs where the installer puts them (the supervisor runs them
    # from there, and takes the console's version from its own build): links
    # to this system's package, made again on every boot, as the volume
    # outlives the VM -- a copy made once would keep the old release's.
    # server.conf: the console's id stays; the version lines follow the pin
    # (the supervisor recreates the container when they change).
    systemd.services.uosserver-setup = {
      description = "Prepare UniFi OS Server's files";
      unitConfig.RequiresMountsFor = "/var/lib/uosserver";
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
      script = ''
        cd /var/lib/uosserver
        rm -rf bin portmap.json mounts.json
        ln -s ${uos}/libexec bin
        ln -s ${uos}/share/portmap.json ${uos}/share/mounts.json .

        conf=/var/lib/uosserver/server.conf
        [ -e $conf ] || echo "UOS_UUID=$(cat /proc/sys/kernel/random/uuid)" > $conf
        set_key() {
          if grep -q "^$1=" $conf; then sed -i "s|^$1=.*|$1=$2|" $conf; else echo "$1=$2" >> $conf; fi
        }
        set_key CONTAINER_VERSION ${containerVersion}
        set_key APP_VERSION ${version}
        set_key NETWORK_MODE pasta
        set_key CONTAINER_IMAGE_NAME ${image}
        chown uosserver:uosserver $conf
        chmod 640 $conf
      '';
    };

    # The pinned image into uosserver's podman (a minute, only when it's new);
    # older ones go once no container uses them.
    systemd.services.uosserver-image = {
      description = "Load UniFi OS Server's container image";
      requires = [ "uosserver-setup.service" "user@${toString uid}.service" ];
      after = [ "uosserver-setup.service" "user@${toString uid}.service" ];
      environment = { XDG_RUNTIME_DIR = "/run/user/${toString uid}"; TMPDIR = "${home}/tmp"; };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "uosserver";
        Group = "uosserver";
        WorkingDirectory = home;
      };
      path = [ podman pkgs.gnugrep ];
      script = ''
        podman image exists ${image} || podman load -i ${uos}/share/image.tar
        podman images --format '{{.Repository}}:{{.Tag}}' | grep '^docker.io/library/uosserver:' \
          | grep -vx ${image} | while read -r old; do podman rmi "$old" || true; done
      '';
    };

    # The installer's two units, with NixOS's paths
    systemd.services.uosserver = {
      description = "UniFi OS Server Service";
      wantedBy = [ "multi-user.target" ];
      requires = [ "uosserver-image.service" ];
      wants = [ "uosserver-updater.service" "network-online.target" ];
      after = [ "uosserver-image.service" "uosserver-updater.service" "network-online.target" ];
      unitConfig = { StartLimitIntervalSec = 60; StartLimitBurst = 3; };
      path = [ podman "/run/wrappers" pkgs.coreutils pkgs.systemd ];
      serviceConfig = {
        ExecStart = "/var/lib/uosserver/bin/uosserver-service";
        WorkingDirectory = "/var/lib/uosserver";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStopSec = 123;
        User = "uosserver";
        Group = "uosserver";
      };
    };
    # Restarts the console when it asks (after a restore, say)
    systemd.services.uosserver-updater = {
      description = "UniFi OS Server Updater Service";
      wantedBy = [ "multi-user.target" ];
      requires = [ "uosserver-setup.service" ];
      after = [ "network.target" "uosserver-setup.service" ];
      unitConfig = { StartLimitIntervalSec = 60; StartLimitBurst = 3; };
      path = [ pkgs.coreutils pkgs.systemd ];
      serviceConfig = {
        ExecStart = "/var/lib/uosserver/bin/updater-service";
        WorkingDirectory = "/var/lib/uosserver";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    environment.systemPackages = [ uos pkgs.curl ];   # `uosserver status`, debugging

    # portmap.json's ports (443 is 11443 outside), and device discovery's
    # answers from the gear's port 10001
    networking.firewall.allowedTCPPorts = [ 11443 8080 8444 8880 8881 8882 5671 6789 9543 28082 ];
    networking.firewall.allowedUDPPorts = [ 3478 5514 10003 ];
    networking.firewall.extraCommands = "iptables -A nixos-fw -p udp --sport 10001 -j nixos-fw-accept";

    services.openssh.enable = lib.mkForce false;
  };

  # Moves the pin to Ubiquiti's latest release, from its firmware API:
  #   nix run .#unifi-os-pin [-- <pin file>]
  # Never backwards. The download lands in the store under fetchurl's name,
  # so the build after it doesn't fetch it again.
  perSystem = { pkgs, ... }: {
    packages.unifi-os-pin = pkgs.writeShellApplication {
      name = "unifi-os-pin";
      runtimeInputs = [ pkgs.curl pkgs.jq pkgs.unzip pkgs.gnutar pkgs.coreutils ];
      # nix comes from the caller's system (its daemon's version).
      text = /* bash */ ''
        pin=''${1:-${pinFile}}
        api='https://fw-update.ui.com/api/firmware-latest?filter=eq~~product~~unifi-os-server&filter=eq~~platform~~linux-x64&filter=eq~~channel~~release'
        fw=$(curl -fsSL "$api" | jq -e '._embedded.firmware
          | if length == 1 then .[0] else error("expected one release, the API gave \(length)") end')
        latest=$(jq -r '.version | ltrimstr("v")' <<<"$fw")
        current=$(jq -er '.version | strings' "$pin")
        if [ "$latest" = "$current" ]; then
          echo "unifi-os: $current is the latest"; exit 0
        fi
        if [ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -1)" != "$latest" ]; then
          echo "unifi-os: the API's latest ($latest) is older than the pin ($current): left as it is"; exit 0
        fi

        url=$(jq -r ._links.data.href <<<"$fw")
        sha256=$(jq -r .sha256_checksum <<<"$fw")
        # Checked against the API's sha256 (and not fetched again when the
        # store has it)
        file=$(nix-prefetch-url --print-path --type sha256 "$url" "$sha256" | tail -1)
        # The image's tag, as the build checks it. (unzip warns about the
        # installer program in front of the zip: exit 1.)
        tag=$({ unzip -p "$file" image.tar || [ $? -eq 1 ]; } | tar -xOf - manifest.json \
          | jq -r '[.[].RepoTags[] | select(startswith("uosserver:")) | ltrimstr("uosserver:")]
                   | if length == 1 then .[0] else error("no single uosserver tag") end')

        jq -n --arg v "$latest" --arg c "$tag" --arg u "$url" --arg s "$sha256" \
          '{version: $v, containerVersion: $c, url: $u, sha256: $s}' > "$pin.new"
        mv "$pin.new" "$pin"
        echo "unifi-os: $current -> $latest (image $tag)"
      '';
    };
  };
}
