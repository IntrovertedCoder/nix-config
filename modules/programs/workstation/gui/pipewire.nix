{ config, self, inputs, ... }: 
let
  c = config.var.colors;
in {
  flake.nixosModules.pipewire = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      slurp
    ];

    systemd.user.services.pipewire.serviceConfig.OOMScoreAdjust = -500;
    systemd.user.services.pipewire-pulse.serviceConfig.OOMScoreAdjust = -500;
    systemd.user.services.wireplumber.serviceConfig.OOMScoreAdjust = -500;
    systemd.user.services."wireplumber@".serviceConfig.OOMScoreAdjust = -500;
    systemd.user.services.xdg-desktop-portal.serviceConfig.OOMScoreAdjust = -500;

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    xdg.portal = {
      enable = true;
      wlr = {
        enable = true;
        settings = {
          screencast = {
            chooser_type = "simple";
            chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
          };
        };
      };

      extraPortals = [ pkgs.xdg-desktop-portal-termfilechooser ];
      config.common = {
        default = [ "gtk" ]; 
        "org.freedesktop.impl.portal.FileChooser" = [ "termfilechooser" ]; 
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      };
      config.mango = {
        default = [ "gtk" ]; 
        "org.freedesktop.impl.portal.FileChooser" = [ "termfilechooser" ]; 
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      };
    };

    home-manager.users.shot = {
      xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
        [filechooser]
        # Generate the wrapper script directly in the Nix store
        cmd=${pkgs.writeShellScript "yazi-wrapper" ''
          #!/usr/bin/env bash
          # The portal passes these 5 arguments:
          multiple="$1"
          directory="$2"
          save="$3"
          path="$4"
          out="$5"

          # Fallback to home directory if the application didn't provide a path
          if [ -z "$path" ]; then
            path="$HOME"
          fi

          # Launch foot running yazi. 
          # Yazi uses --chooser-file to write the selected item to the output file 
          # so the application knows what you picked.
          ${pkgs.foot}/bin/foot -- ${pkgs.yazi}/bin/yazi --chooser-file="$out" "$path"
        ''}
      '';
    };
  };
}
