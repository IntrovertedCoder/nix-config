{ self, inputs, ... }: {
  flake.nixosModules.sshd = { pkgs, lib, config, ...}: {
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
      ports = [ 20530 ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AllowTcpForwarding = false;
        ClientAliveCountMax = 2;
        MaxAuthTries = 3;
        MaxSessions = 4;
        TCPKeepAlive = false;
        PermitRootLogin = "no";
        AllowAgentForwarding = false;
        LogLevel = "VERBOSE";
      };
    };

    services.fail2ban = {
      enable = true; 
      jails.sshd = {
        settings = {
          enabled = true;
          port = lib.concatStringsSep "," (builtins.map toString config.services.openssh.ports);
          backend = "systemd";
        };
      };
    };
  };
}
