{ self, inputs, ... }: {
  flake.nixosModules.mullvad = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      directories = [
        "/etc/mullvad-vpn"
      ];
      users.shot = {
        directories = [
          ".config/Mullvad VPN"
        ];
      };
    };

    environment.systemPackages = with pkgs; [
    ];
    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
