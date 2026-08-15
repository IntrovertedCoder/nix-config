{ self, inputs, ... }: {
  flake.nixosModules.games = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.steam
      self.nixosModules.heroic
      self.nixosModules.prismlauncher

      self.nixosModules.mangohud
      self.nixosModules.gamescope
      self.nixosModules.gamemode
    ];
    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          "Games"
        ];
      };
    };
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "gmgsmh" /*bash*/ ''
        GAMESCOPE_FLAGS="''${GAMESCOPE_FLAGS:--f}"

        exec ${pkgs.uwsm}/bin/uwsm app -s app-games.slice -- \
          ${pkgs.gamemode}/bin/gamemoderun \
          ${pkgs.gamescope}/bin/gamescope $GAMESCOPE_FLAGS -- \
          ${pkgs.mangohud}/bin/mangohud "$@"
        '')

      (writeShellScriptBin "gmmh" /*bash*/ ''
        exec ${pkgs.uwsm}/bin/uwsm app -s app-games.slice -- \
          ${pkgs.gamemode}/bin/gamemoderun \
          ${pkgs.mangohud}/bin/mangohud "$@"
        '')

      (writeShellScriptBin "mh" /*bash*/ ''
        exec ${pkgs.uwsm}/bin/uwsm app -s app-games.slice -- \
          ${pkgs.mangohud}/bin/mangohud "$@"
        '')
    ];

    systemd.user.slices.app-games = {
      sliceConfig = {
        OOMScoreAdjust = 500; # Tell the kernel to kill games before anything else
      };
    };

    home-manager.users.shot = {
      xdg.mimeApps.enable = true;
      home.packages = with pkgs; [
      ];
    };
  };
}
