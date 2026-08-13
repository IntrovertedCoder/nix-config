{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.wshowkeys = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    programs.wshowkeys = {
      enable = true;
      package = inputs.wshowkeys.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
    home-manager.users.shot = {
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Toggle screen keystrokes overlay"
        prefix = "keys"
        cmd = "if pkill -x wshowkeys; then true; else systemd-run --user --unit=wshowkeys-overlay wshowkeys -a bottom -t 1000 -b ${c.black}7f -f ${c.white}ff -F \"Hack Nerd Font Mono 30\" -l 960; fi"
        with_argument = false
      '';
    };
  };
}
