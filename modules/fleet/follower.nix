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
        for interactive desktops (manual pull is the primary path there:
        you still choose when to run it).

        This only controls the *timer*. Passwordless sudo for the commands
        fleet-pull-update needs (see security.sudo.extraRules below) is
        granted unconditionally to any host that imports fleetFollower at
        all, regardless of this option -- the whole build/download phase
        runs unprivileged and can take hours on a slow connection, with
        sudo only needed once at the very end to activate and reboot; a
        manual run that then hangs on a password prompt no one's there to
        answer defeats "start it and walk away," which is the actual
        point of the manual path, not a reason to require babysitting it.
        `shot` is already in `wheel` (full, password-gated sudo), so this
        doesn't raise the account's privilege ceiling, it only removes the
        prompt for actions it could already perform.
      '';
    };

    config = let
      fleetPullUpdate = pkgs.writeShellApplication {
        name = "fleet-pull-update";
        # openssh: `git fetch`/merge over the SSH remote shells out to
        # `ssh` -- see the identical note in vmtest-orchestrator.nix,
        # same bug would hit here too.
        #
        # Deliberately no pkgs.sudo here: that's the unprivileged store
        # copy, not NixOS's real setuid wrapper at /run/wrappers/bin/sudo
        # -- including it would actually be worse than omitting it, since
        # it'd shadow the real one earlier in PATH. Real sudo comes from
        # the systemd service's Environment=PATH below (unattended path)
        # or is already on PATH in any normal interactive session (manual
        # path).
        runtimeInputs = [ pkgs.git pkgs.nh pkgs.systemd pkgs.openssh ];
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
          # elevation, silently via the unconditional NOPASSWD sudo rule
          # below -- no password prompt at all, whether this run was
          # triggered manually or by the opt-in unattended timer.
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

      # Unconditional (not gated on autoUpdate.enable) -- see the option
      # doc above for why the manual path needs this too.
      security.sudo.extraRules = [{
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
          # See the identical note in vmtest-orchestrator.nix -- real setuid
          # sudo only lives at /run/wrappers/bin, needed both for nh's own
          # elevation and for the script's explicit `sudo systemctl reboot`.
          Environment = [
            "HOME=/home/shot"
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
          ];
          ExecStart = "${fleetPullUpdate}/bin/fleet-pull-update";
        };
      };
    };
  };
}
