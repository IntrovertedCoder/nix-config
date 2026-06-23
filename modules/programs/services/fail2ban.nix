{ self, inputs, ... }: {
  flake.nixosModules.fail2ban = { pkgs, config, lib, ... }: {
    config = {
      # Base configuration applied whenever Fail2ban is activated
      services.fail2ban = {
        maxretry = 3;
        bantime = "1h";
        bantime-increment = {
          enable = true;
          # Don't specify multiplers as default is 2^n (1 2 4 8 16...) until maxtime is reached
          # One week
          maxtime = "168h"; 
        };
      };

      # Only bind-mount the state folder if the service is actually enabled
      preservation.preserveAt."/persistent" = lib.mkIf config.services.fail2ban.enable {
        directories = [
          { directory = "/var/lib/fail2ban"; mode = "0750"; }
        ];
      };
    };
  };
}
