{ self, inputs, ... }: {
  flake.nixosModules.swaybg = { pkgs, config, lib, ... }: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.wallpaper
    ];

    home-manager.users.shot = {
      wayland.windowManager.mango.autostart_sh = ''
        ${pkgs.swaybg}/bin/swaybg ${lib.concatMapStringsSep " " (m:
          "-o ${m.name} -i ${config.var.wallpapers.${m.name}} -m fill"
        ) config.var.monitors} &
      '';
    };
  };
}
