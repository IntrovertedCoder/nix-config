{ lib, ... }: {
  # TODO(remove before real cluster): test-lab-only access so Claude Code
  # can rebuild the test nodes unattended (`nixos-rebuild --target-host
  # root@<node>` and nixos-anywhere reinstalls) with the ~/.ssh/nixos key.
  # Imported only for hosts with `test = true` in _hosts.nix (see
  # hosts.nix). To remove: delete this file and the
  # `lib.optional host.test self.nixosModules.clusterTestAccess` line in
  # modules/cluster/hosts.nix, then rebuild -- root login goes back to "no".
  flake.nixosModules.clusterTestAccess = { config, lib, ... }: {
    services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
    # nixos-anywhere talks to the kexec installer on 22 after the first hop,
    # so cluster-testlab.sh just uses 22 throughout.
    services.openssh.ports = [ 22 ];
    users.users.root.openssh.authorizedKeys.keys =
      config.users.users.shot.openssh.authorizedKeys.keys;

    # SSH from the home LAN (the testLan side door), ping for debugging.
    var.nftFirewall.interfaces.${config.var.cluster.host.testLan} = {
      allowedTCPPorts = config.services.openssh.ports;
      allowPing = true;
    };
  };
}
