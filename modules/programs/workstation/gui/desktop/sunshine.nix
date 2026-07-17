{ self, inputs, ... }: {
  flake.nixosModules.sunshine = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".config/sunshine"
        ];
      };
    };
    services.sunshine = {
        enable = true;
        autoStart = true;
        capSysAdmin = true;
    };
  };
}
