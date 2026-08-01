{ self, inputs, ... }: {
  flake.nixosModules.polkit = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      services.polkit-gnome.enable = true;
    };
  };
}
