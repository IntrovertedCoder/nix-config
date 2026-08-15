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

        OBS_PREFIX=""
        if [ "$OBS_CAP" = "1" ]; then
          if command -v obs-gamecapture >/dev/null 2>&1; then
            OBS_PREFIX="obs-gamecapture"
          else
            echo "Warning: OBS_CAP=1 but obs-gamecapture is not installed. Skipping capture." >&2
          fi
        fi

        exec ${pkgs.uwsm}/bin/uwsm app -s app-games.slice -- \
          ${pkgs.gamemode}/bin/gamemoderun \
          ${pkgs.gamescope}/bin/gamescope $GAMESCOPE_FLAGS -- \
          $OBS_PREFIX \
          ${pkgs.mangohud}/bin/mangohud "$@"
        '')

      (writeShellScriptBin "gmmh" /*bash*/ ''
        OBS_PREFIX=""
        if [ "$OBS_CAP" = "1" ]; then
          if command -v obs-gamecapture >/dev/null 2>&1; then
            OBS_PREFIX="obs-gamecapture"
          else
            echo "Warning: OBS_CAP=1 but obs-gamecapture is not installed. Skipping capture." >&2
          fi
        fi

        exec ${pkgs.uwsm}/bin/uwsm app -s app-games.slice -- \
          ${pkgs.gamemode}/bin/gamemoderun \
          $OBS_PREFIX \
          ${pkgs.mangohud}/bin/mangohud "$@"
        '')

      (writeShellScriptBin "mh" /*bash*/ ''
        OBS_PREFIX=""
        if [ "$OBS_CAP" = "1" ]; then
          if command -v obs-gamecapture >/dev/null 2>&1; then
            OBS_PREFIX="obs-gamecapture"
          else
            echo "Warning: OBS_CAP=1 but obs-gamecapture is not installed. Skipping capture." >&2
          fi
        fi

        exec ${pkgs.uwsm}/bin/uwsm app -s app-games.slice -- \
          $OBS_PREFIX \
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
