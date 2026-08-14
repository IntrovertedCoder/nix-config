{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.mangohud = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    home-manager.users.shot = {
      xdg.configFile."MangoHud/MangoHud.conf".text = /*toml*/ ''
        legacy_layout=false
        gpu_list=0
        gpu_stats
        gpu_load_change
        vram
        gpu_temp
        cpu_stats
        cpu_load_change
        cpu_temp
        ram
        procmem
        fps
        fps_color_change
        fps_metrics=avg,0.01
        background_alpha=0.5
        table_columns=2
        toggle_hud=Shift_R+F12
        font_size=20
        font_file=${pkgs.nerd-fonts.hack}/share/fonts/truetype/NerdFonts/Hack/HackNerdFontMono-Regular.ttf
        gpu_color=${c.lred}
        vram_color=${c.lorange}
        cpu_color=${c.lyellow}
        ram_color=${c.lgreen}
        engine_color=${c.lblue}
        fps_value=60,90
        fps_color=${c.dred},${c.dmagenta},${c.dcyan}
        gpu_load_value=50,90
        gpu_load_color=${c.white},${c.orange},${c.red}
        cpu_load_value=50,90
        cpu_load_color=${c.white},${c.orange},${c.red}
        background_color=${c.black}
        text_color=${c.white}
      '';
      home.packages = with pkgs; [
        mangohud
      ];
    };
  };
}
