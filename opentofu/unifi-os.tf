# UniFi OS Server (design doc, Next: the controller's move off the Network
# Server, whose standalone releases end with Network 10.6). Ubiquiti ships
# it only as an installer for Debian/Ubuntu that runs the console in podman,
# so it gets a Debian VM on Ceph, set up by cloud-init on first boot. Its
# state lives in the VM's disk (podman volumes under /home/uosserver); the
# nodes copy its Network backups like the old controller's (unifi.nix).
#
# Built beside the old controller, at infra .11, until the switch by backup
# and restore. Its web UI: https://10.4.0.11:11443 (from Trusted).

resource "incus_instance" "unifi_os" {
  name     = "unifi-os"
  type     = "virtual-machine"
  image    = "images:debian/13/cloud"
  profiles = ["default"] # root disk on remote; evacuate = migrate

  config = {
    "limits.cpu"                = "2"
    "limits.memory"             = "4GiB" # ~3 GiB in use after setup (2 is the minimum)
    "boot.autostart"            = "true"
    "migration.stateful"        = "true" # live around planned reboots, like v1
    "cloud-init.network-config" = local.unifi_os_network
    "cloud-init.user-data"      = local.unifi_os_user_data
  }

  # Untagged on the trunk = infra. Fixed MAC (infra .11), like the routers'.
  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype = "bridged"
      parent  = "br-trunk"
      hwaddr  = "02:74:af:04:00:0b"
      name    = "eth0"
    }
  }

  # The installer wants 10 GiB free; podman's images and the console's
  # data take about 4.
  device {
    name = "root"
    type = "disk"
    properties = {
      pool = incus_storage_pool.remote.name
      path = "/"
      size = "24GiB"
    }
  }

  # A new image from images: mustn't replace the console (its state is on
  # this disk): Debian updates itself inside.
  lifecycle { ignore_changes = [image] }
}

locals {
  unifi_os_network = <<-EOT
    # Static on infra, beside the old controller (10.4.0.10) until the switch.
    version: 2
    ethernets:
      infra:
        match: { macaddress: "02:74:af:04:00:0b" }
        set-name: eth0
        addresses: [10.4.0.11/21] # infra is a /21: the gear is at .4.x
        routes: [{ to: 0.0.0.0/0, via: 10.4.0.1 }]
        nameservers: { addresses: [10.4.0.1] }
        dhcp4: false
        dhcp6: false
        accept-ra: false
  EOT

  unifi_os_user_data = <<-EOT
    #cloud-config
    # UniFi OS Server, installed once on first boot: Ubiquiti's installer
    # (podman-based), pinned and checked against the sha256 fw-update.ui.com
    # gives for it. Later versions come from UniFi's own updater (Control
    # Plane), not from here.
    package_update: true
    packages: [podman, uidmap, slirp4netns, curl, ca-certificates]
    write_files:
      - path: /usr/local/sbin/unifi-os-install
        permissions: "0755"
        content: |
          #!/bin/sh
          set -eu
          url=https://fw-download.ubnt.com/data/unifi-os-server/5172-linux-x64-5.1.42-12e9e3cf-8f8b-4e54-928c-76b80a10c8a4.42-x64
          sha=f6111e9396a42c74016f5dde9b01fbef486a6fe69efe137935e6e38b7c22f94d
          [ -e /var/lib/uosserver/server.conf ] && exit 0
          curl -fsSL --retry 3 -o /root/uos.bin "$url"
          echo "$sha  /root/uos.bin" | sha256sum -c -
          chmod +x /root/uos.bin
          /root/uos.bin --non-interactive
          rm -f /root/uos.bin
    runcmd:
      - [ sh, -c, "/usr/local/sbin/unifi-os-install > /var/log/unifi-os-install.log 2>&1" ]
  EOT
}

# The VM was built by hand first (2026-10-26) to try the installer: the
# first apply adopts it. Remove this block after that apply.
import {
  to = incus_instance.unifi_os
  id = "unifi-os"
}
