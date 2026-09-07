{ self, inputs, ... }: {
  flake.nixosModules.networkManager = { pkgs, ...}: {
    networking.networkmanager = {
      enable = true;
      dns = "systemd-resolved";
    };

    networking.nameservers = [
      "1.1.1.1#cloudfalre-dns.com"
      "1.0.0.1#cloudfalre-dns.com"
    ];

    services.resolved = {
      enable = true;
      # Opportunistic since Mullvad's DNS doesn't support DoT
      settings.Resolve.DNSOverTLS = "opportunistic";
    };
  };
}
