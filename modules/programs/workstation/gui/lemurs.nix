{ self, inputs, ... }: {
  flake.nixosModules.lemurs = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    users.users.shot.extraGroups = [ "seat" ];
    services.displayManager.lemurs.enable = true;
  };
}
