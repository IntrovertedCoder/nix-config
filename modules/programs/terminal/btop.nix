{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.btop = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.btop = {
        enable = true;

        settings = {
          color_theme = "/home/shot/.config/btop/themes/guildmaster.theme";
          vim_keys = true;
          proc_sorting = "memory";
          proc_tree = true;
          proc_gradient = false;
          proc_left = true;
          proc_aggregate = true;
          cpu_graph_upper = "total";
          cpu_graph_lower = "user";
          show_gpu_info = "On";
          clock_format = "%H";
        };

        themes = {
          guildmaster = /* php */ ''
            theme[main_bg]        ="#${c.black}"
            theme[main_fg]        ="#${c.white}"
            theme[title]          ="#${c.white}"
            theme[hi_fg]          ="#${c.black2}"
            theme[selected_bg]    ="#${c.green}"
            theme[selected_fg]    ="#${c.white}"
            theme[inactive_fg]    ="#${c.grey2}"
            theme[graph_text]     ="#${c.white}"
            theme[meter_bg]       ="#${c.grey2}"
            theme[proc_misc]      ="#${c.magenta}"
            theme[cpu_box]        ="#${c.magenta}"
            theme[mem_box]        ="#${c.green}"
            theme[net_box]        ="#${c.red}"
            theme[proc_box]       ="#${c.blue}"
            theme[div_line]       ="#${c.grey2}"
            theme[temp_start]     ="#${c.magenta}"
            theme[temp_mid]       ="#${c.orange}"
            theme[temp_end]       ="#${c.red}"
            theme[cpu_start]      ="#${c.lorange}"
            theme[cpu_mid]        ="#${c.orange}"
            theme[cpu_end]        ="#${c.dorange}"
            theme[free_start]     ="#${c.lpink}"
            theme[free_mid]       ="#${c.pink}"
            theme[free_end]       ="#${c.dpink}"
            theme[cached_start]   ="#${c.lcyan}"
            theme[cached_mid]     ="#${c.cyan}"
            theme[cached_end]     ="#${c.dcyan}"
            theme[available_start]="#${c.lorange}"
            theme[available_mid]  ="#${c.orange}"
            theme[available_end]  ="#${c.dorange}"
            theme[used_start]     ="#${c.lgreen}"
            theme[used_mid]       ="#${c.green}"
            theme[used_end]       ="#${c.dgreen}"
            theme[download_start] ="#${c.lred}"
            theme[download_mid]   ="#${c.red}"
            theme[download_end]   ="#${c.dred}"
            theme[upload_start]   ="#${c.lcyan}"
            theme[upload_mid]     ="#${c.cyan}"
            theme[upload_end]     ="#${c.dcyan}"
            theme[process_start]  ="#${c.lgreen}"
            theme[process_mid]    ="#${c.green}"
            theme[process_end]    ="#${c.dgreen}"
            '';
        };
      };
    };
  };
}
