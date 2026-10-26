{ self, inputs, lib, ... }: let
  lan = import ./_lan.nix;
  infra = lan.segments.infra;
  # The console's address follows its MAC, the way the routers' ids do:
  # 02:74:af:04:00:<host> is infra .<host>. One image then serves at any of
  # these; OpenTofu's hwaddr picks the address (unifi-os.tf).
  hosts = [ 10 11 12 ];
  macFor = host: "02:74:af:04:00:${lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString host))}";
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
  # stays. A new console version = a new pin below; turn the console's own
  # automatic updates off in its settings (Control Plane, Updates): they
  # would install outside the flake.
  # It has no SSH: `incus exec unifi-os -- ...` from a node.
  flake.nixosConfigurations.unifi-os = inputs.nixpkgs.lib.nixosSystem {
    modules = [ self.nixosModules.unifiOsServer ];
  };

  flake.nixosModules.unifiOsServer = { config, lib, pkgs, modulesPath, ... }: let
    # From Ubiquiti's firmware API (fw-update.ui.com/api/firmware-latest,
    # product unifi-os-server, platform linux-x64).
    version = "5.1.42";
    containerVersion = "c9603dec9010";   # the image's tag, in the installer's image.tar
    image = "docker.io/library/uosserver:${containerVersion}";

    uos = pkgs.stdenv.mkDerivation {
      pname = "unifi-os-server";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://fw-download.ubnt.com/data/unifi-os-server/5172-linux-x64-5.1.42-12e9e3cf-8f8b-4e54-928c-76b80a10c8a4.42-x64";
        sha256 = "f6111e9396a42c74016f5dde9b01fbef486a6fe69efe137935e6e38b7c22f94d";
      };
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
      # Where the installer puts them; the supervisor runs them from there
      "C+ /var/lib/uosserver/bin - - - - ${uos}/libexec"
      "C+ /var/lib/uosserver/portmap.json - - - - ${uos}/share/portmap.json"
      "C+ /var/lib/uosserver/mounts.json - - - - ${uos}/share/mounts.json"
      # The supervisor calls /usr/bin/podman, with its own PATH
      "L+ /usr/bin/podman - - - - ${podman}/bin/podman"
    ];

    # server.conf: the console's id stays; the version lines follow the pin
    # (the supervisor recreates the container when they change).
    systemd.services.uosserver-setup = {
      description = "Prepare UniFi OS Server's files";
      unitConfig.RequiresMountsFor = "/var/lib/uosserver";
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
      script = ''
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
}
