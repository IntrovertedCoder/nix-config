# Cluster members as plain data -- the one place hardware differs between
# the test cluster and the real one. Modules never hardcode an interface
# name or disk path; they read it from here. (The leading underscore keeps
# import-tree from loading this as a flake module; hosts.nix imports it.)
#
# `id` drives every derived address: mesh loopback fd9a:7af:74af:ff::<id>,
# OpenFabric NET 49.0001.0000.0000.000<id>.00.
let
  testNode = id: hostKey: {
    inherit id;
    test = true;
    # SSH host key, pre-seeded at install from secrets/hostkeys/<name>.age so
    # a reinstalled node keeps its identity and can decrypt agenix secrets on
    # first boot. Also an agenix recipient (see secrets.nix).
    inherit hostKey;
    mgmt = "ens18";          # home LAN, DHCP (UniFi reservation by MAC)
    ring = [ "ens19" "ens20" ];  # Thunderbolt ring stand-in, point-to-point bridges
    wan = "ens21";           # router VMs' WAN -- VLAN 30 in the test lab
    trunk = "ens22";         # Trusted / IoT / Guest VLAN trunk
    # Router VM (router.nix). The real nodes pass the WAN NIC through by PCI
    # address; the test VMs can't (nested passthrough), so their router gets
    # a macvtap on `wan` instead.
    wanPci = null;
    # VLAN IDs on the trunk. The test lab's only need to avoid VLAN 30 (the
    # test WAN) and the home network's VLANs; the real cluster uses its own.
    vlans = { trusted = 31; iot = 32; guest = 33; transit = 34; };
    ringMtu = 1500;          # real Thunderbolt links run 65520
    # One per cluster -- the real cluster gets its own (uuidgen).
    cephFsid = "6b1f3c2e-0d7a-4f43-9c1e-7a52e1d0b9a4";
    # 2 OSDs in a ~10 GB VM; the 4 GiB default per OSD doesn't fit.
    osdMemoryTarget = 1536 * 1024 * 1024;
    bootDisk = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_test-node${toString id}-boot";
    osdDisks = [
      "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_test-node${toString id}-osd-a"
      "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_test-node${toString id}-osd-b"
    ];
  };
in {
  test-node1 = testNode 1 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKbf3UN2FTuOSYsc2HscLPvWH03Sk7yjbludv1Vh2uGB root@test-node1";
  test-node2 = testNode 2 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHB20Q+1Mu38pAuD58DiEyMitY6wufEFheQ+O/neFbej root@test-node2";
  test-node3 = testNode 3 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIJIO7kEZdac+ekLgmGPRI9996osv5WofnmheN6Yex4S root@test-node3";
}
