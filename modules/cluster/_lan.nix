# The cluster's LAN side as plain data, shared by the router VMs (router.nix),
# the nodes' management address (node.nix) and the rescue installers. These
# prefixes never change between sites; the VLAN IDs do, so those live in
# _hosts.nix. (The leading underscore keeps import-tree from loading this.)
#
# On every segment .1 / ::1 is the gateway (the VRRP master router).
# Management is the Trusted VLAN: each node has a static address there
# (_hosts.nix lanId), outside the routers' DHCP pools (.100-.249).
{
  ula = "fd9a:7af:74af::/48";
  segments = {
    trusted = { v4 = "10.1.0";  v6 = "fd9a:7af:74af:1";  dhcp = true;  onLink = true; };
    iot     = { v4 = "10.2.0";  v6 = "fd9a:7af:74af:2";  dhcp = true;  onLink = false; };
    guest   = { v4 = "10.3.0";  v6 = null;               dhcp = true;  onLink = true; };
    transit = { v4 = "10.91.0"; v6 = "fd9a:7af:74af:91"; dhcp = false; onLink = true; };
  };
}
