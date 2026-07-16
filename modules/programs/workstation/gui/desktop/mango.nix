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
            "Alt,Return,spawn,foot"
          ];
        };
      };
    };
  };
}
