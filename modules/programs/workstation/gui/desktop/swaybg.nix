{ self, inputs, ... }: {
  flake.nixosModules.swaybg = { pkgs, config, lib, ... }: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.wallpaper
    ];

    home-manager.users.shot = {
      # A systemd user unit (rather than mango's autostart_sh) so that
      # home-manager restarts it whenever the generated wallpaper store
      # paths change -- e.g. after editing var.wallpaperColors -- instead
      # of leaving the old image loaded until the next full re-login.
      systemd.user.services.swaybg = {
        Unit = {
          Description = "Wallpaper daemon";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.swaybg}/bin/swaybg ${lib.concatMapStringsSep " " (m:
            "-o ${m.name} -i ${config.var.wallpapers.${m.name}} -m fill"
          ) config.var.monitors}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
