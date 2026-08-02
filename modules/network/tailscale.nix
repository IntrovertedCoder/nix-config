{ self, inputs, ... }: {
  flake.nixosModules.tailscale = { pkgs, ...}: {
    preservation.preserveAt."/persistent" = {
      directories = [
        "/var/lib/tailscale"
      ];
    };
    imports = [
    ];
    environment.systemPackages = with pkgs; [
    ];
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "both";
      extraSetFlags = [ "--advertise-exit-node" ];
      extraUpFlags = [ "--accept-routes" ];
      interfaceName = "tailscale0";
    };
    home-manager.users.shot = {
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Toggle tailscale"
        prefix = "ts"
        # Runs silently in the background since no password prompt is needed
        cmd = "if tailscale status | grep -q \"stopped\"; then tailscale up; else tailscale down; fi;"
        with_argument = false
      '';
    };
  };
}
