{ self, inputs, ... }: {
  flake.nixosModules.fleetFollower = { pkgs, lib, config, ... }: {
    imports = [ self.nixosModules.fleetCacheClient ];

    options.var.fleet.autoUpdate.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run fleet-pull-update unattended on a weekly timer, instead of only
        as a manual command. Off by default -- intended for future headless
        service VMs with nobody around to run it by hand. Leave this false
        for interactive desktops (manual pull is the primary path there).

        When true, this also grants the `shot` user narrowly-scoped
        passwordless sudo for exactly the commands fleet-pull-update needs
        to run unattended (nh's build/activation step, and the final
        reboot) -- see security.sudo.extraRules below. `shot` is already in
        `wheel` (full, password-gated sudo), so this doesn't raise the
        account's privilege ceiling, it only removes the password prompt
        for actions it could already perform.
      '';
    };

    config = let
      fleetPullUpdate = pkgs.writeShellApplication {
        name = "fleet-pull-update";
        # openssh: `git fetch`/merge over the SSH remote shells out to
        # `ssh` -- see the identical note in vmtest-orchestrator.nix,
        # same bug would hit here too.
        runtimeInputs = [ pkgs.git pkgs.nh pkgs.sudo pkgs.systemd pkgs.openssh ];
        text = ''
          cd /home/shot/nix-config

          if ! git fetch origin || ! git merge --ff-only origin/main; then
            echo "fleet-pull-update: git pull failed (diverged checkout?)" >&2
            git checkout -- flake.lock
            exit 1
          fi

          # Deliberately no --update/-u: build exactly what vmtest already
          # validated and pushed, never independently newer inputs. Since
          # this is a local `nh os boot`, cache-client.nix's substituter
          # kicks in wherever vmtest already built the matching store paths
          # -- normally a full cache hit. nh handles its own privilege
          # elevation (prompts for the shot password interactively when run
          # by hand; silently uses the NOPASSWD sudo rule below when
          # var.fleet.autoUpdate.enable made this run unattended).
          # Explicit flake path, not relying on NH_FLAKE -- matters for the
          # opt-in unattended timer (var.fleet.autoUpdate.enable), which
          # like any systemd service never sources the interactive shell
          # profile that normally sets it.
          if nh os boot -H ${lib.escapeShellArg config.networking.hostName} /home/shot/nix-config; then
            sudo systemctl reboot
          else
            echo "fleet-pull-update: build/boot failed" >&2
            exit 1
          fi
        '';
      };
    in {
      environment.systemPackages = [ fleetPullUpdate ];

      home-manager.users.shot.programs.yazi.settings.keymap.mgr.prepend_keymap = [
        {
          on = [ "n" "p" ];
          run = "shell 'fleet-pull-update' --block";
          desc = "Pull + apply the latest fleet update and reboot";
        }
      ];

      security.sudo.extraRules = lib.mkIf config.var.fleet.autoUpdate.enable [{
        users = [ "shot" ];
        commands = [
          { command = "${pkgs.systemd}/bin/systemctl reboot"; options = [ "NOPASSWD" ]; }
          # Wildcard on the store path is unavoidable -- it changes per
          # build. Narrower than root, not perfect; same tradeoff most
          # unattended nixos-rebuild setups (deploy-rs, colmena) accept.
          { command = "/nix/store/*/bin/switch-to-configuration"; options = [ "NOPASSWD" ]; }
          { command = "/nix/store/*/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
        ];
      }];

      systemd.timers.fleet-pull-update = lib.mkIf config.var.fleet.autoUpdate.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Fri *-*-* 02:00:00";
          Persistent = true;
        };
      };

      systemd.services.fleet-pull-update = lib.mkIf config.var.fleet.autoUpdate.enable {
        description = "Automatic fleet-pull-update (opt-in, see var.fleet.autoUpdate.enable)";
        serviceConfig = {
          Type = "oneshot";
          User = "shot";
          WorkingDirectory = "/home/shot/nix-config";
          Environment = "HOME=/home/shot";
          ExecStart = "${fleetPullUpdate}/bin/fleet-pull-update";
        };
      };
    };
  };
}
