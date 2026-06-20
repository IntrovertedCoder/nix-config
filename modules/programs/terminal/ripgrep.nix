{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.ripgrep = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.ripgrep = {
        enable = true;
        arguments = [
          "--glob=!.git"
          "--hidden"
          "--colors=path:fg:0x${c.magentar},0x${c.magentag},0x${c.magentab}"
          "--colors=line:fg:0x${c.greenr},0x${c.greeng},0x${c.greenb}"
          "--colors=column:fg:0x${c.lgreenr},0x${c.lgreeng},0x${c.lgreenb}"
          "--colors=match:fg:0x${c.redr},0x${c.redg},0x${c.redb}"
          "--colors=match:style:bold"
          "--colors=highlight:fg:0x${c.white1r},0x${c.white1g},0x${c.white1b}"
          "--smart-case"
          "--follow"
          "--heading"
          "--line-number"
        ];
      };
    };
  };
}
