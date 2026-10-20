# The cluster's LAN side as plain data, shared by the router VMs (router.nix),
# the nodes' management address (node.nix) and the rescue installers. These
# prefixes never change between sites; the VLAN IDs do, so those live in
# _hosts.nix. (The leading underscore keeps import-tree from loading this.)
#
# Client segments are /21s, 10.<segment>.0.0 - 10.<segment>.7.255, and the
# third octet says where an address came from:
#
#   10.<seg>.0.x   fixed: .1 the gateway (the VRRP master router), .2-.4 the
#                  routers, nodes at their atomic number (_hosts.nix lanId)
#   10.<seg>.1.x   DHCP from router 1    (.1-.254)
#   10.<seg>.2.x   DHCP from router 2
#   10.<seg>.3.x   DHCP from router 3
#   10.<seg>.4.x   DHCP reservations (below): the same address from every router,
#                  so a router failover never renumbers them; host = atomic number
#   10.<seg>.5-7.x spare
#
# The second octet is the segment, never 10.0 (a common ISP default: the
# cluster must fit behind whatever upstream it lands on). Transit has no
# DHCP and stays a /24. Management is the Trusted segment.
let
  # "10.1.0" -> "10.1"
  base = s: builtins.head (builtins.match "([0-9]+\\.[0-9]+)\\..*" s.v4);
in {
  ula = "fd9a:7af:74af::/48";
  segments = {
    trusted = { v4 = "10.1.0";  plen = 21; v6 = "fd9a:7af:74af:1";  dhcp = true;  onLink = true; };
    iot     = { v4 = "10.2.0";  plen = 21; v6 = "fd9a:7af:74af:2";  dhcp = true;  onLink = false; };
    # Guests get plain DNS: no ad blocking (adblock = false).
    guest   = { v4 = "10.3.0";  plen = 21; v6 = null;               dhcp = true;  onLink = true; adblock = false; };
    # Network gear (UniFi switches, APs) and the UniFi controller. The one
    # UNTAGGED segment on the trunk: factory-fresh gear asks for DHCP there.
    # DHCP only answers devices that say they are UniFi (dhcpClass).
    infra   = {
      v4 = "10.4.0"; plen = 21; v6 = null; dhcp = true; onLink = true; untagged = true; dhcpClass = "ubnt";
      reservations = [
        { name = "copper"; host = 29; mac = "8c:ed:e1:12:61:31"; }   # USW Flex 2.5G 5 (test switch)
        { name = "neon";   host = 10; mac = "9c:05:d6:79:8f:2e"; }   # UniFi AP
      ];
    };
    transit = { v4 = "10.91.0"; plen = 24; v6 = "fd9a:7af:74af:91"; dhcp = false; onLink = true; };
  };

  # "10.1.0.0/21"
  v4net = s: "${s.v4}.0/${toString s.plen}";
  # A DHCP router's pool, and a reservation's address.
  v4pool = s: router: "${base s}.${toString router}.1 - ${base s}.${toString router}.254";
  v4reserved = s: host: "${base s}.4.${toString host}";

  # The Incus OVN network for services (ovn.nix, cluster-ovn-bootstrap),
  # behind OVN's router. That router's uplink address on the transit VLAN is
  # pinned, so the routers can route the services network to it statically.
  services = { v4 = "10.90.0"; v6 = "fd9a:7af:74af:90"; };
  ovnUplink = { v4 = "10.91.0.10"; v6 = "fd9a:7af:74af:91::10"; };
}
