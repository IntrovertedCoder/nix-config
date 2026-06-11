{ self, inputs, ... }: {
  flake.nixosModules.ssh = { pkgs, ...}: {
    users.users.shot.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdnAXOp0q2Ehf9KwXo2KXOD/UDnam7uyezYnUm1WdnA arik"
    ];
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };
  };
}
