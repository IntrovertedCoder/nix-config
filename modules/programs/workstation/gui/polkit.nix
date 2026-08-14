{ self, inputs, ... }: {
  flake.nixosModules.polkit = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    systemd.user.services.polkit-gnome.serviceConfig.OOMScoreAdjust = -500;
    home-manager.users.shot = {
      services.polkit-gnome.enable = true;
    };
  };
}
