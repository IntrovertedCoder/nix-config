{ self, inputs, ... }: {
  flake.nixosModules.ssh = { pkgs, ...}: {
    preservation.preserveAt."/persistent" = {
      files = [
        { file = "/etc/ssh/ssh_host_ed25519_key"; mode = "0600"; }
        { file = "/etc/ssh/ssh_host_ed25519_key.pub"; mode = "0644"; }
        { file = "/etc/ssh/ssh_host_rsa_key"; mode = "0600"; }
        { file = "/etc/ssh/ssh_host_rsa_key.pub"; mode = "0644"; }
      ];
    };
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
