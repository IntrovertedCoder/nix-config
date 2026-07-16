{ self, inputs, ... }: {
  flake.nixosModules.tailscale = { pkgs, ...}: {
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
