{ self, inputs, config, pkgs, ... }:
let
  c = config.var.colors;
in
{
  flake.nixosModules.tuigreet = { pkgs, ...}: {
    preservation.preserveAt."/persistent" = {
      files = [
        "/var/cache/tuigreet/lastuser"
      ];
    };
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      tuigreet
    ];
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start mango.desktop'";
          user = "greeter";
        };
      };
    };
  };
}
