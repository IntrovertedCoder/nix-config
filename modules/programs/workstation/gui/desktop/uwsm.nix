{ self, inputs, ... }: {
  flake.nixosModules.uwsm = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    programs.uwsm = {
      enable = true;
      waylandCompositors.mango = {
        prettyName = "Mango";
        comment = "Mango managed by uwsm";
        binPath = "/home/shot/.nix-profile/bin/mango";
      };
    };
    home-manager.users.shot = {
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "freeze"
        prefix = "fz"
        cmd = "systemctl --user list-units --type=scope,service --state=running --no-legend | fsel --dmenu | awk '{print $1}' | xargs -r systemctl --user freeze"

        [[modules]]
        description = "thaw"
        prefix = "th"
        cmd = "systemctl --user list-units --type=scope,service --state=running --no-legend | fsel --dmenu | awk '{print $1}' | xargs -r systemctl --user thaw"
      '';

      home.packages = with pkgs; [
      ];
    };
  };
}
