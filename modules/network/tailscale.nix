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
  };
}
