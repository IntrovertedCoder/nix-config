{ lib, ... }: {
  flake.nixosModules.customFirewall = { lib, config, ... }: let
    cfg = config.var.firewall;

    isIPv6 = ip: builtins.match ".*:.*" ip != null;

    portRangeType = lib.types.submodule {
      options = {
        from = lib.mkOption { type = lib.types.int; };
        to = lib.mkOption { type = lib.types.int; };
      };
    };

  in {
    options.var.firewall = {
      untrustedInterfaces = lib.mkOption {
        description = "Interfaces that strictly drop all traffic unless explicitly allowed. Takes priority over all standard NixOS firewall options (openFirewall, allowedTCPPorts, etc).";
        default = {};
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            ipGroups = lib.mkOption {
              description = "Groups of IPs with specific port allowances.";
              default = {};
              type = lib.types.attrsOf (lib.types.submodule {
                options = {
                  ips = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [];
                    description = "List of IPs (v4 or v6) for this group. Mixed families are supported.";
                  };
                  allowedTCPPorts = lib.mkOption {
                    type = lib.types.listOf lib.types.int;
                    default = [];
                  };
                  allowedUDPPorts = lib.mkOption {
                    type = lib.types.listOf lib.types.int;
                    default = [];
                  };
                  allowedTCPPortRanges = lib.mkOption {
                    type = lib.types.listOf portRangeType;
                    default = [];
                  };
                  allowedUDPPortRanges = lib.mkOption {
                    type = lib.types.listOf portRangeType;
                    default = [];
                  };
                };
              });
            };
            generalAllowedTCPPorts = lib.mkOption {
              type = lib.types.listOf lib.types.int;
              default = [];
              description = "TCP ports open to all traffic on this interface.";
            };
            generalAllowedUDPPorts = lib.mkOption {
              type = lib.types.listOf lib.types.int;
              default = [];
              description = "UDP ports open to all traffic on this interface.";
            };
            generalAllowedUDPPortRanges = lib.mkOption {
              type = lib.types.listOf portRangeType;
              default = [];
              description = "UDP port ranges open to all traffic on this interface.";
            };
            generalAllowedTCPPortRanges = lib.mkOption {
              type = lib.types.listOf portRangeType;
              default = [];
              description = "TCP port ranges open to all traffic on this interface.";
            };
          };
        });
      };
    };

    config = lib.mkIf (cfg.untrustedInterfaces != {}) {

      networking.firewall.extraCommands =
        let
          isIPv6 = ip: builtins.match ".*:.*" ip != null;

          ifaceRules = iface: ifaceCfg:
            let
              groupRules = lib.concatStringsSep "\n" (lib.mapAttrsToList (_groupName: groupCfg:
                let
                  v4 = lib.filter (ip: !(isIPv6 ip)) groupCfg.ips;
                  v6 = lib.filter isIPv6 groupCfg.ips;
                in
                lib.concatStringsSep "\n" (
                  map (ip: lib.concatStringsSep "\n" (
                    map (port: "iptables  -A untrusted-ifaces -i ${iface} -s ${ip} -p tcp --dport ${toString port} -j nixos-fw-accept") groupCfg.allowedTCPPorts
                    ++ map (port: "iptables  -A untrusted-ifaces -i ${iface} -s ${ip} -p udp --dport ${toString port} -j nixos-fw-accept") groupCfg.allowedUDPPorts
                    ++ map (range: "iptables  -A untrusted-ifaces -i ${iface} -s ${ip} -p tcp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept") groupCfg.allowedTCPPortRanges
                    ++ map (range: "iptables  -A untrusted-ifaces -i ${iface} -s ${ip} -p udp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept") groupCfg.allowedUDPPortRanges
                  )) v4
                  ++
                  map (ip: lib.concatStringsSep "\n" (
                    map (port: "ip6tables -A untrusted-ifaces -i ${iface} -s ${ip} -p tcp --dport ${toString port} -j nixos-fw-accept") groupCfg.allowedTCPPorts
                    ++ map (port: "ip6tables -A untrusted-ifaces -i ${iface} -s ${ip} -p udp --dport ${toString port} -j nixos-fw-accept") groupCfg.allowedUDPPorts
                    ++ map (range: "ip6tables -A untrusted-ifaces -i ${iface} -s ${ip} -p tcp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept") groupCfg.allowedTCPPortRanges
                    ++ map (range: "ip6tables -A untrusted-ifaces -i ${iface} -s ${ip} -p udp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept") groupCfg.allowedUDPPortRanges
                  )) v6
                )
              ) ifaceCfg.ipGroups);

              generalTCPRules = lib.concatStringsSep "\n" (map (port: ''
                iptables  -A untrusted-ifaces -i ${iface} -p tcp --dport ${toString port} -j nixos-fw-accept
                ip6tables -A untrusted-ifaces -i ${iface} -p tcp --dport ${toString port} -j nixos-fw-accept
              '') ifaceCfg.generalAllowedTCPPorts);

              generalUDPRules = lib.concatStringsSep "\n" (map (port: ''
                iptables  -A untrusted-ifaces -i ${iface} -p udp --dport ${toString port} -j nixos-fw-accept
                ip6tables -A untrusted-ifaces -i ${iface} -p udp --dport ${toString port} -j nixos-fw-accept
              '') ifaceCfg.generalAllowedUDPPorts);

              generalUDPRangeRules = lib.concatStringsSep "\n" (map (range: ''
                iptables  -A untrusted-ifaces -i ${iface} -p udp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept
                ip6tables -A untrusted-ifaces -i ${iface} -p udp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept
              '') ifaceCfg.generalAllowedUDPPortRanges);

              generalTCPRangeRules = lib.concatStringsSep "\n" (map (range: ''
                iptables  -A untrusted-ifaces -i ${iface} -p tcp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept
                ip6tables -A untrusted-ifaces -i ${iface} -p tcp --dport ${toString range.from}:${toString range.to} -j nixos-fw-accept
              '') ifaceCfg.generalAllowedTCPPortRanges);
            in ''
              # === Untrusted interface: ${iface} ===
              ${groupRules}
              ${generalTCPRules}
              ${generalUDPRules}
              ${generalTCPRangeRules}
              ${generalUDPRangeRules}
              # DROP catch-all — everything else on ${iface} is denied
              iptables  -A untrusted-ifaces -i ${iface} -j DROP
              ip6tables -A untrusted-ifaces -i ${iface} -j DROP
            '';
        in ''
          # Create (or flush) the untrusted-ifaces chain
          iptables  -N untrusted-ifaces 2>/dev/null || iptables  -F untrusted-ifaces
          ip6tables -N untrusted-ifaces 2>/dev/null || ip6tables -F untrusted-ifaces

          # ALLOW RETURN TRAFFIC: Accept replies to connections initiated by this machine
          iptables  -A untrusted-ifaces -m conntrack --ctstate RELATED,ESTABLISHED -j nixos-fw-accept
          ip6tables -A untrusted-ifaces -m conntrack --ctstate RELATED,ESTABLISHED -j nixos-fw-accept

          # Insert jump at position 1 in nixos-fw, before any global openFirewall rules
          iptables  -I nixos-fw 1 -j untrusted-ifaces
          ip6tables -I nixos-fw 1 -j untrusted-ifaces

          ${lib.concatStringsSep "\n" (lib.mapAttrsToList ifaceRules cfg.untrustedInterfaces)}
        '';

      networking.firewall.extraStopCommands = ''
        iptables  -D nixos-fw -j untrusted-ifaces 2>/dev/null || true
        ip6tables -D nixos-fw -j untrusted-ifaces 2>/dev/null || true
        iptables  -F untrusted-ifaces 2>/dev/null || true
        ip6tables -F untrusted-ifaces 2>/dev/null || true
        iptables  -X untrusted-ifaces 2>/dev/null || true
        ip6tables -X untrusted-ifaces 2>/dev/null || true
      '';
    };
  };
}
