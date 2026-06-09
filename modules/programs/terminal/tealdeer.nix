{ self, inputs, ... }: {
  flake.nixosModules.tealdeer = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      # tealdeer
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        tealdeer
      ];
      home.activation.tealdeer = ''
        ${pkgs.tealdeer}/bin/tldr --update
      '';
    };
  };
}
