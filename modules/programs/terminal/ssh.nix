{ self, inputs, ... }: {
  flake.nixosModules.ssh = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          { directory = ".ssh"; mode = "0700"; }
        ];
      };
    };

    home-manager.users.shot = {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          "*" = {
            ServerAliveInterval = 60;
            AddKeysToAgent = "yes";
            ForwardAgent = "no";
          };
          "10.123.*.*" = {
            User = "shot";
            IdentityFile = "~/.ssh/nixos";
            IdentitiesOnly = "yes";
          };
        };
      };
    };
  };
}
