{ self, inputs, ... }: {
  flake.nixosModules.zoxide = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".local/share/zoxide"
        ];
      };
    };

    home-manager.users.shot = {
      programs.zoxide = {
        enable = true;
        enableBashIntegration = true;
        enableFishIntegration = true;
      };
      home.shellAliases = {
      };
      home.sessionVariables = {
        _ZO_EXCLUDES = "^/persistent/.*";
      };
      home.packages = with pkgs; [
      ];
    };
  };
}
