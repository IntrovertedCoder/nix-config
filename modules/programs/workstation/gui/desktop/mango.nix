{ self, inputs, ... }: {
  flake.nixosModules.mango = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      inputs.mangowm.nixosModules.mango
    ];
    environment.systemPackages = with pkgs; [
    ];
    programs.mangowc.enable = true;
    hardware.graphics.enable = true;
    home-manager.users.shot = {
      imports = [
        inputs.mangowm.hmModules.mango
      ];
      wayland.windowManager.mango = {
        enable = true;
        settings = {
          bind = [
            # Launch Apps
            "Alt,Return,spawn,foot"

            "ALT+SHIFT+CTRL,r,reload_config"
            "ALT+SHIFT,q,killclient"
            # Focus window
            "ALT,h,focusdir,left"
            "ALT,j,focusdir,down"
            "ALT,k,focusdir,up"
            "ALT,l,focusdir,right"
            # Move window
            "ALT+SHFIT,h,exchange_client,left"
            "ALT+SHIFT,j,exchange_client,down"
            "ALT+SHIFT,k,exchange_client,up"
            "ALT+SHIFT,l,exchange_client,right"

            # Window status
            "ALT,f,togglefullscreen"
            "ALT+SHIFT,f,togglefloating"
            "ALT,i,minimized"
            "ALT+SHIFT,i,restore_minimized"

            # Tag switching
            "ALT,1,view,1,0"
            "ALT,2,view,2,0"
            "ALT,3,view,3,0"
            "ALT,4,view,4,0"
            "ALT,5,view,5,0"
            "ALT,6,view,6,0"
            "ALT,7,view,7,0"
            "ALT,8,view,8,0"
            "ALT,9,view,9,0"
            "ALT,0,view,0,0"

            # Tag moving
            "ALT+SHIFT,1,tagsilent,1,0"
            "ALT+SHIFT,2,tagsilent,2,0"
            "ALT+SHIFT,3,tagsilent,3,0"
            "ALT+SHIFT,4,tagsilent,4,0"
            "ALT+SHIFT,5,tagsilent,5,0"
            "ALT+SHIFT,6,tagsilent,6,0"
            "ALT+SHIFT,7,tagsilent,7,0"
            "ALT+SHIFT,8,tagsilent,8,0"
            "ALT+SHIFT,9,tagsilent,9,0"
            "ALT+SHIFT,0,tagsilent,0,0"
          ];
        };
      };
    };
  };
}
