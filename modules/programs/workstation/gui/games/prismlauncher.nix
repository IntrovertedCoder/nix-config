{ self, inputs, ... }: {
  flake.nixosModules.prismlauncher = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          "Games/Prism"
        ];
      };
    };
    home-manager.users.shot = {
      home.sessionVariables = {
        PRISMLAUNCHER_DATA_DIR = "$HOME/Games/Prism";
      };
      home.packages = with pkgs; [
        (prismlauncher.override {
          # Bundles the exact Java versions you need directly into the launcher
          jdks = [
            jdk21 # For Minecraft 1.20.5+ (Latest mods)
            jdk8  # For Minecraft 1.16.5 and older (1.12.2 and 1.7.10 packs)
            jdk17 # Optional: For Minecraft 1.17 -> 1.20.4 transitional packs
          ];
        })
      ];
    };
  };
}
