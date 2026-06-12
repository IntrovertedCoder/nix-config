{ self, inputs, ... }: {
  flake.nixosModules.fd = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      programs.fd = {
        enable = true;
        ignores = [
          ".git/"
        ];
      };
    };
  };
}
