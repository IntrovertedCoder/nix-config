{ self, inputs, lib, ... }: let
  hosts = import ./_hosts.nix;
in {
  flake.nixosConfigurations = lib.mapAttrs (name: host: inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.global
      self.nixosModules.clusterNode
      self.nixosModules.clusterTime
      self.nixosModules.clusterCeph
      self.nixosModules.clusterIncus
      self.nixosModules.clusterTailscale
      self.nixosModules.clusterTools
      self.nixosModules.clusterHealth
      self.nixosModules.clusterRouter
      self.nixosModules.clusterOvn
      self.nixosModules.clusterUnifi
      self.nixosModules.clusterUpdate
      self.nixosModules.clusterDisko
      self.nixosModules.user-shot
      self.nixosModules.sshd
      self.nixosModules.nftFirewall
      {
        nixpkgs.hostPlatform = "x86_64-linux";
        networking.hostName = name;
        var.cluster = { inherit name host hosts; };
        # Weekly, an hour after vmtest's update (update.nix, _schedule.nix).
        var.cluster.autoUpdate.enable = true;
      }
    ] ++ lib.optional host.test self.nixosModules.clusterTestAccess;
  }) hosts;
}
