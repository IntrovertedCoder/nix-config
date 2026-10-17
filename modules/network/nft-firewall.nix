{ lib, ... }: {
  # nftables replacement for customFirewall (modules/network/firewall.nix),
  # needed anywhere Incus runs -- the Incus module asserts the nftables
  # backend, and the nftables backend asserts extraCommands is empty.
  #
  # Same idea as customFirewall, simpler shape: only `trustedInterfaces`
  # (tailscale0 by default) see the normal NixOS firewall rules. Every
  # other interface drops everything except the ports listed for it under
  # `interfaces.<name>` -- including ports a service opened globally with
  # `openFirewall = true`, which is the whole point.
  #
  # How: an extra inet table whose input chain runs just before NixOS's own
  # (priority filter - 5). In nftables a drop is final across every base
  # chain, while an accept only ends that one chain, so this chain can veto
  # NixOS's global allows but never grant more than NixOS's chain does. The
  # per-interface ports are therefore mirrored into
  # networking.firewall.interfaces so NixOS's chain accepts them too.
  flake.nixosModules.nftFirewall = { lib, config, ... }: let
    cfg = config.var.nftFirewall;

    portRangeType = lib.types.submodule {
      options = {
        from = lib.mkOption { type = lib.types.port; };
        to = lib.mkOption { type = lib.types.port; };
      };
    };

    toSet = ports: ranges: lib.concatStringsSep ", " (
      map toString ports ++ map (r: "${toString r.from}-${toString r.to}") ranges
    );

    quoted = names: lib.concatStringsSep ", " (map (n: ''"${n}"'') names);

    ifaceRules = iface: icfg: let
      tcp = toSet icfg.allowedTCPPorts icfg.allowedTCPPortRanges;
      udp = toSet icfg.allowedUDPPorts icfg.allowedUDPPortRanges;
    in ''
      ${lib.optionalString (tcp != "") ''iifname "${iface}" tcp dport { ${tcp} } accept''}
      ${lib.optionalString (udp != "") ''iifname "${iface}" udp dport { ${udp} } accept''}
      ${lib.optionalString icfg.allowPing ''iifname "${iface}" icmp type echo-request accept''}
      ${lib.optionalString icfg.allowPing ''iifname "${iface}" icmpv6 type echo-request accept''}
      ${icfg.extraRules}
    '';
  in {
    options.var.nftFirewall = {
      trustedInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tailscale0" ];
        description = ''
          Interfaces that get the normal NixOS firewall (and everything in
          networking.firewall.trustedInterfaces is accepted outright). Every
          interface not listed here is locked down.
        '';
      };

      interfaces = lib.mkOption {
        default = {};
        description = "Per-interface allowances on locked-down interfaces.";
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            allowedTCPPorts = lib.mkOption { type = lib.types.listOf lib.types.port; default = []; };
            allowedUDPPorts = lib.mkOption { type = lib.types.listOf lib.types.port; default = []; };
            allowedTCPPortRanges = lib.mkOption { type = lib.types.listOf portRangeType; default = []; };
            allowedUDPPortRanges = lib.mkOption { type = lib.types.listOf portRangeType; default = []; };
            allowPing = lib.mkOption { type = lib.types.bool; default = false; };
            extraRules = lib.mkOption {
              type = lib.types.lines;
              default = "";
              example = ''iifname "ens18" ip saddr 10.123.0.51 tcp dport 9090 accept'';
              description = ''
                Raw nftables rules for this interface (e.g. source-restricted
                ports). Anything accepted here must also be accepted by
                NixOS's chain -- use networking.firewall.extraInputRules for
                the matching allow.
              '';
            };
          };
        });
      };
    };

    config = {
      networking.nftables.enable = true;
      networking.firewall.enable = true;
      networking.firewall.trustedInterfaces = cfg.trustedInterfaces;

      networking.firewall.interfaces = lib.mapAttrs (_: icfg: {
        inherit (icfg) allowedTCPPorts allowedUDPPorts allowedTCPPortRanges allowedUDPPortRanges;
      }) cfg.interfaces;

      networking.nftables.tables."nft-lockdown" = {
        family = "inet";
        content = /* nft */ ''
          chain input {
            type filter hook input priority filter - 5; policy accept;

            iifname { ${quoted ([ "lo" ] ++ cfg.trustedInterfaces)} } accept

            # IPv6 doesn't work without neighbour discovery / router adverts.
            # Before the conntrack check: multicast ND can be marked invalid.
            icmpv6 type != { nd-redirect, 139 } icmpv6 type != echo-request accept
            ip6 daddr fe80::/64 udp dport 546 accept comment "DHCPv6 client"

            ct state invalid drop
            ct state { established, related } accept

            ${lib.concatStrings (lib.mapAttrsToList ifaceRules cfg.interfaces)}

            drop
          }
        '';
      };
    };
  };
}
