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
      ];
      programs.tealdeer = {
        enable = true;
        settings = {
          display = {
            compact = true;
            use_pager = true;
          };
          updates = {
            auto_update = true;
            auto_update_interval_hours = 168; # 1 week
          };
        };
      };
    };
  };
}
