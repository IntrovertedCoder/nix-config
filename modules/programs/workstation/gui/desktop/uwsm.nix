{ self, inputs, ... }: {
  flake.nixosModules.uwsm = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    programs.uwsm = {
      enable = true;
      waylandCompositors.mango = {
        prettyName = "Mango";
        comment = "Mango managed by uwsm";
        binPath = "/home/shot/.nix-profile/bin/mango";
      };
    };
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
