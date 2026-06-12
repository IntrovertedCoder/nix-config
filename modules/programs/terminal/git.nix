{ self, inputs, ... }: {
  flake.nixosModules.git = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.git.enable = true;

    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.git = {
        enable = true;
        delta.enable = true;
        settings = {
          user = {
            email = "NATrotnic@gmail.com";
            name = "IntrovertedCoder";
          };
        };
      };
      home.activation.git = /* bash */''
        if [ ! -f ~/.ssh/github ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -C "NATrotinc@gmail.com" -f ~/.ssh/github
        fi
      '';
      programs.ssh.settings = {
        "github.com" = {
          hostname = "github.com";
          identityFile = "~/.ssh/github";
        };
      };
    };
  };
}
