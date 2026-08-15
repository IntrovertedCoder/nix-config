{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.mako = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      libnotify
    ];
    home-manager.users.shot = {
      services.mako = {
        enable = true;
        settings = {
          background-color = "#${c.black}";
          text-color = "#${c.white}";
          progress-color = "#${c.cyan}";
          border-color = "#${c.blue}";
          border-size = 2;
          default-timeout = 5000;

          "urgency=low" = {
            border-color = "#${c.green}";
            default-timeout = 2000;
          };

          "urgency=critical" = {
            border-color = "#${c.red}";
            default-timeout = 0;
            background-color = "#${c.red}";
            text-color = "#${c.white}";
          };
        };
      };

      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Notification history"
        prefix = "nh"
        cmd = "${pkgs.writeShellScript "otter-notif-history" ''
          { ${pkgs.mako}/bin/makoctl list -j; ${pkgs.mako}/bin/makoctl history -j; } | ${pkgs.jq}/bin/jq -r '.[] | "[\( (.urgency // "normal")[:1] | ascii_upcase )] [\(.app_name // "System")] \(.summary // "No Summary") ➜ \( (.body // "") | gsub("\n"; " ") )"' | fsel --dmenu
        ''}"
      '';

      home.packages = with pkgs; [
      ];
      wayland.windowManager.mango.settings.bind = [
        "ALT,m,spawn_shell,makoctl dismiss"
        "ALT+SHIFT,m,spawn_shell, makoctl dismiss -a"
      ];
    };
  };
}
