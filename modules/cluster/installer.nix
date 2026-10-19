{ self, inputs, lib, ... }: let
  hosts = import ./_hosts.nix;
in {
  # Rescue installer image per node, meant to stay plugged in (USB stick)
  # behind the boot disk in the firmware's boot order: if the boot disk dies
  # or won't boot, the node falls through to this and waits.
  #
  #   nix build .#nixosConfigurations.<node>-installer.config.system.build.isoImage
  #
  # Reachable two ways, both root with your key only:
  # - management: the node's own static address on the Trusted VLAN of the
  #   trunk, and its link-local fe80::<lanId>, which answers with every
  #   router down (test lab: also the home-LAN side door, by DHCP);
  # - the Thunderbolt mesh, at the node's usual mesh address (same FRR config
  #   as the node, mesh.nix), through a healthy node:
  #   ssh -J shot@<healthy-node>:20530 root@fd9a:7af:74af:ff::<id>
  # The WAN port stays unaddressed. No host key is baked in -- it
  # would sit unencrypted on the stick -- so it makes its own at each boot.
  # It never touches a disk by itself. `rescue-report` says why a node died.
  flake.nixosConfigurations = lib.mapAttrs' (name: host:
    lib.nameValuePair "${name}-installer" (inputs.nixpkgs.lib.nixosSystem {
      modules = [
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        self.nixosModules.clusterMesh
        self.nixosModules.nftFirewall
        ({ lib, pkgs, ... }: let
          # Same derivation as ceph.nix's osdIds: node1 -> 0 1, node2 -> 2 3, ...
          osdIds = lib.imap0 (i: _: toString ((host.id - 1) * 2 + i)) host.osdDisks;
          lan = import ./_lan.nix;
          mgmtSeg = lan.segments.trusted;
          mgmtIf = "${host.trunk}.${toString host.vlans.trusted}";

          # One paste-ready answer to "why did this node die?". Read-only:
          # the dead boot disk is mounted ro, nothing is changed.
          rescueReport = pkgs.writeShellApplication {
            name = "rescue-report";
            runtimeInputs = with pkgs; [
              coreutils util-linux gnugrep gawk jq smartmontools nvme-cli lvm2
              lm_sensors iproute2 frr systemd btrfs-progs
              mtools efibootmgr                    # read the ESP without mounting it; boot entries
            ];
            text = ''
              c() { echo "\$ $*"; "$@" 2>&1 || true; echo; }
              mnt=$(mktemp -d)
              trap 'umount -q "$mnt"/* 2>/dev/null || true; rm -rf "$mnt"' EXIT

              echo "## Rescue report: ${name} ($(date -u '+%F %T UTC'))"
              echo
              echo '```'

              echo "### Disks"
              c lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,PARTLABEL
              for d in $(smartctl --scan | cut -d' ' -f1); do
                c smartctl -H -A "$d"
              done
              for d in /dev/nvme?; do
                [ -e "$d" ] || continue
                c nvme smart-log "$d"
                c nvme error-log -e 5 "$d"
              done

              echo "### Ceph OSD volumes (this node should have: ${lib.concatStringsSep " " osdIds})"
              c lvs -o lv_name,vg_name,lv_size,lv_tags --noheadings

              echo "### The dead system (boot disk ${host.bootDisk})"
              # Its ESP first: with only that destroyed, the journal below looks
              # fine and nothing else says why the node didn't boot (seen in
              # testing). mtools reads the FAT filesystem straight off the
              # partition -- no mount, nothing written.
              esp=/dev/disk/by-partlabel/disk-main-ESP
              export MTOOLS_SKIP_CHECK=1   # don't refuse a partition over its CHS geometry
              echo "--- ESP ($esp):"
              if [ ! -e "$esp" ]; then
                echo "VERDICT: no ESP partition (disk-main-ESP) -- the firmware has nothing to boot from"
              elif ! mdir -i "$esp" -b ::/ >/dev/null 2>&1; then
                echo "VERDICT: the ESP has no readable FAT filesystem -- the firmware can't boot from it,"
                echo "which is why this node fell through to the rescue installer."
                c blkid -p "$esp"
              else
                missing=""
                for f in ::/EFI/BOOT/BOOTX64.EFI ::/EFI/systemd/systemd-bootx64.efi; do
                  mdir -i "$esp" -b "$f" >/dev/null 2>&1 || missing="$missing ''${f#::}"
                done
                entries=$(mdir -i "$esp" -b ::/loader/entries 2>/dev/null | grep -c '\.conf$' || true)
                if [ -n "$missing" ] || [ "$entries" = 0 ]; then
                  echo "VERDICT: the ESP is readable but incomplete --''${missing:+ missing$missing;} $entries boot entries"
                else
                  echo "VERDICT: ESP readable, systemd-boot present, $entries boot entries"
                fi
                c mdir -i "$esp" -/ -b ::/
              fi
              echo "--- firmware boot entries (BootOrder; the boot disk should come before this stick):"
              c efibootmgr
              echo

              root=/dev/disk/by-partlabel/disk-main-root
              if [ -e "$root" ]; then
                mkdir -p "$mnt/log" "$mnt/persistent"
                if mount -o ro,subvol=log "$root" "$mnt/log" 2>/dev/null; then
                  c journalctl --directory="$mnt/log/journal" --list-boots --no-pager
                  echo "--- last 100 lines of its last boot (a clean shutdown ends with 'Journal stopped'):"
                  c journalctl --directory="$mnt/log/journal" -b 0 -n 100 --no-pager -o short-iso
                  echo "--- errors in its last boot:"
                  c journalctl --directory="$mnt/log/journal" -b 0 -p err -n 40 --no-pager -o short-iso
                else
                  echo "couldn't mount its /var/log (subvolume 'log') -- filesystem damaged?"
                fi
                if mount -o ro,subvol=persistent "$root" "$mnt/persistent" 2>/dev/null; then
                  echo "--- kernel crash records (pstore):"
                  c ls -la "$mnt/persistent/var/lib/systemd/pstore"
                fi
              else
                echo "no root partition (disk-main-root) on the boot disk -- wiped, dead, or never installed"
              fi

              echo "### Hardware now"
              c sensors
              c journalctl -k -b -p err --no-pager -o short-iso

              echo "### Network"
              c ip -br addr
              c vtysh -c "show openfabric neighbor"
              echo '```'
            '';
          };
        in {
          nixpkgs.hostPlatform = "x86_64-linux";
          var.cluster = { inherit name host hosts; };
          networking.hostName = "${name}-installer";

          # Only management and the mesh: no NetworkManager/wifi from the
          # installer profile, nothing on the WAN. Management is the node's
          # own static address and link-local on the Trusted VLAN of the trunk
          # (node.nix), so it's reachable exactly where the node was -- with
          # the routers down, by fe80::<lanId>. The node isn't running while
          # this is, so the address is free.
          networking.networkmanager.enable = lib.mkForce false;
          networking.wireless.enable = lib.mkForce false;
          systemd.network.netdevs."25-mgmt" = {
            netdevConfig = { Kind = "vlan"; Name = mgmtIf; };
            vlanConfig.Id = host.vlans.trusted;
          };
          systemd.network.networks = {
            "20-trunk" = {
              matchConfig.Name = host.trunk;
              vlan = [ mgmtIf ];
              networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; };
            };
            "25-mgmt" = {
              matchConfig.Name = mgmtIf;
              address = [
                "${mgmtSeg.v4}.${toString host.lanId}/${toString mgmtSeg.plen}"
                "${mgmtSeg.v6}::${toString host.lanId}/64"
                "fe80::${toString host.lanId}/64"
              ];
              gateway = [ "${mgmtSeg.v4}.1" ];
              dns = [ "${mgmtSeg.v4}.1" ];
              networkConfig = { LinkLocalAddressing = "no"; IPv6AcceptRA = false; ConfigureWithoutCarrier = true; };
            };
          } // lib.optionalAttrs ((host.testLan or null) != null) {
            # Test lab: the home-LAN side door, with its default route (a
            # rescue system may need internet when the routers are down).
            "10-testlan" = {
              matchConfig.Name = host.testLan;
              networkConfig = { DHCP = "ipv4"; IPv6AcceptRA = true; };
              # Same client ID as the node, so it gets the node's usual address.
              dhcpV4Config.ClientIdentifier = "mac";
            };
          };

          boot.kernelModules = [ "thunderbolt" "thunderbolt_net" ];

          services.openssh = {
            enable = true;
            settings = {
              PermitRootLogin = lib.mkForce "prohibit-password";
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
            };
          };
          users.users.root.openssh.authorizedKeys.keys =
            self.nixosConfigurations.${name}.config.users.users.shot.openssh.authorizedKeys.keys;

          # Nothing trusted; SSH and ping on management (and the test side door) and the ring links.
          var.nftFirewall.trustedInterfaces = [ ];
          var.nftFirewall.interfaces = lib.genAttrs ([ mgmtIf ] ++ lib.optional ((host.testLan or null) != null) host.testLan ++ host.ring) (_: {
            allowedTCPPorts = [ 22 ];
            allowPing = true;
          });

          # No internet is guaranteed down here, so `nix shell` can't be
          # relied on: bring what debugging a dead node needs.
          environment.systemPackages = with pkgs; [
            rescueReport
            smartmontools nvme-cli hdparm fio            # is the disk dying?
            ddrescue testdisk                            # get data off it
            pciutils usbutils dmidecode lm_sensors       # what hardware, how hot
            memtester stress-ng                          # RAM test, reproduce heat
            ethtool iperf3 tcpdump mtr dnsutils          # links, ring throughput
            tmux vim htop rsync jq                       # tmux: survive SSH drops
          ];

          system.stateVersion = "26.05";
        })
      ];
    })) hosts;
}
