{ self, inputs, ... }: {
  flake.nixosModules.hypridlesuspend = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    services.logind = {
      settings = {
        Login = {
          HandleLidSwitch = "ignore";
          HandleLidSwitchExternalPower = "ignore";
          HandleLidSwitchDocked = "ignore";
        };
      };
    };

    services.acpid = {
      enable = true;
      handlers.lidSuspend = {
        event = "button/lid.*";
        action = ''
          if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null; then
            ${pkgs.util-linux}/bin/logger "ACPI: Lid close detected"

            if ! ${pkgs.procps}/bin/pidof nh > /dev/null && \
               ! ${pkgs.procps}/bin/pidof nixos-rebuild > /dev/null && \
               ! /run/wrappers/bin/sudo -u shot XDG_RUNTIME_DIR=/run/user/$(${pkgs.coreutils}/bin/id -u shot) ${pkgs.systemd}/bin/systemctl --user is-active --quiet suspend-block; then

              ${pkgs.util-linux}/bin/logger "ACPI: No blocks active. Triggering suspend."
              ${pkgs.systemd}/bin/systemctl suspend
            else
              ${pkgs.util-linux}/bin/logger "ACPI: Suspend blocked! (nh, nixos-rebuild, or suspend-block is active)"
            fi
          fi
        '';
      };
    };

    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Toggle suspend lock"
        prefix = "sl"
        cmd = "if systemctl --user is-active --quiet suspend-block; then systemctl --user stop suspend-block; else systemd-run --user --unit=suspend-block sleep infinity; fi"
        with_argument = false
      '';
      services.hypridle = {
        settings = {
          listener = [
            {
              timeout = 900;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
            {
              timeout = 1800;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
            {
              timeout = 2700;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
            {
              timeout = 3600;
              on-timeout = "pidof nh > /dev/null || pidof nixos-rebuild > /dev/null || systemctl --user is-active --quiet suspend-block || systemctl suspend";
            }
          ];
        };
      };
    };
  };
}
