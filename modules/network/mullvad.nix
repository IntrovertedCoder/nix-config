{ self, inputs, ... }: {
  flake.nixosModules.mullvad = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
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
