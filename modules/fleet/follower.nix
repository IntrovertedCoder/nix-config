{ self, inputs, ... }: {
  flake.nixosModules.fleetFollower = { pkgs, lib, config, ... }: {
    imports = [ self.nixosModules.fleetCacheClient ];

    options.var.fleet.autoUpdate.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run fleet-pull-update-reboot unattended on a weekly timer, instead of
        only as a manual command. Off by default -- intended for future headless
        service VMs with nobody around to run it by hand. Leave this false
        for interactive desktops (manual pull is the primary path there:
        you still choose when to run it).

        This also gates the passwordless sudo rule below
        (security.sudo.extraRules): nixos-rebuild/switch-to-configuration
        with unrestricted arguments is realistically root-equivalent, since
        sudoers has no way to further restrict what flags get passed, so
        that carve-out is only granted to hosts that actually run this
        unattended with nobody there to type a password. `shot` is already
        in `wheel` (full, password-gated sudo) on every host regardless --
        this option only ever controls whether the *prompt* is skipped, not
        whether the account can do the thing at all.

        Interactive/manual runs don't need this: fleet-pull-update primes
        `sudo -v` up front (prompts once, immediately, while you're still
        there) and keeps the credential alive in the background for the
        duration of the build, so the real elevation at the end -- after a
        build that can take hours -- doesn't need to prompt again.
      '';
    };

    config = let
      # Shared by the manual reboot/shutdown/cache-only commands and the
      # opt-in unattended timer (which always uses the reboot variant --
      # see ExecStart below). powerCmd is the only thing that differs
      # between the three manual variants; null means "build and cache
      # only, don't reboot or shut down -- leave that decision to me".
      mkFleetPullUpdate = { name, powerCmd }: pkgs.writeShellApplication {
        inherit name;
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

          # Only when there's a real terminal to prompt in (the manual/
          # otter-launcher path): authenticate sudo immediately, before the
          # potentially hours-long build, and keep the credential refreshed
          # in the background. `nh os boot` builds unprivileged and only
          # elevates separately (its own internal sudo call) for the final
          # switch-to-configuration/set-profile step, and (for the reboot/
          # shutdown variants) the final `sudo systemctl` call below needs
          # it too -- both can hit an unanswerable password prompt after a
          # long build with nobody there to answer it. The unattended timer
          # (var.fleet.autoUpdate.enable) has no TTY for this to work with
          # at all, and doesn't need it: it relies on the NOPASSWD sudoers
          # rule below instead, gated to hosts that opted in.
          if [ -t 0 ]; then
            sudo -v
            ( while sleep 60; do sudo -n true || true; done ) &
            keepalive_pid=$!
            trap 'kill "$keepalive_pid" 2>/dev/null || true' EXIT
          fi

          if ! git fetch origin || ! git merge --ff-only origin/main; then
            echo "${name}: git pull failed (diverged checkout?)" >&2
            git checkout -- flake.lock
            exit 1
          fi

          # Deliberately no --update/-u: build exactly what vmtest already
          # validated and pushed, never independently newer inputs. Since
          # this is a local `nh os boot`, cache-client.nix's substituter
          # kicks in wherever vmtest already built the matching store paths
          # -- normally a full cache hit.
          # Explicit flake path, not relying on NH_FLAKE -- matters for the
          # opt-in unattended timer (var.fleet.autoUpdate.enable), which
          # like any systemd service never sources the interactive shell
          # profile that normally sets it.
          if ! nh os boot -H ${lib.escapeShellArg config.networking.hostName} /home/shot/nix-config; then
            echo "${name}: build/boot failed" >&2
            exit 1
          fi
          ${if powerCmd == null then ''
          echo "${name}: built and cached -- run 'sudo systemctl reboot' (or 'poweroff') whenever you're ready."
          '' else ''
          # sudo here (not bare systemctl): the interactive/active-session
          # case would work without it via logind's default polkit rule,
          # but this same script also backs the unattended timer, which
          # has no active session for polkit to cover -- it needs the
          # NOPASSWD sudoers rule below instead. The sudo -v keep-alive
          # above makes this silent for manual runs either way.
          sudo systemctl ${powerCmd}
          ''}
        '';
      };

      # Plain fleet-pull-update: pull + build + cache only, no reboot or
      # shutdown -- leaves the "when" up to whoever runs it by hand. The
      # reboot/shutdown variants are the explicit opt-in ones.
      fleetPullUpdate = mkFleetPullUpdate { name = "fleet-pull-update"; powerCmd = null; };
      fleetPullUpdateReboot = mkFleetPullUpdate { name = "fleet-pull-update-reboot"; powerCmd = "reboot"; };
      fleetPullUpdateShutdown = mkFleetPullUpdate { name = "fleet-pull-update-shutdown"; powerCmd = "poweroff"; };
    in {
      environment.systemPackages = [ fleetPullUpdate fleetPullUpdateReboot fleetPullUpdateShutdown ];

      home-manager.users.shot = {
        # Appended to launcher.nix's config text rather than editing that
        # file directly -- same reasoning as not touching yazi.nix above:
        # launcher.nix is imported unconditionally by every workstation
        # host, including ones that never import fleetFollower, so these
        # commands belong here instead. Unwrapped `cmd` (no `uwsm app`/
        # new-foot-window wrapping), same as the existing "nmtui"/
        # "systemctl-tui" modules in launcher.nix -- it runs directly in
        # otter-launcher's own terminal, so all of git/nh/nixos-rebuild's
        # output stays visible instead of vanishing into a background unit.
        xdg.configFile."otter-launcher/config.toml".text = lib.mkAfter ''

          [[modules]]
          description = "fleet pull update (cache only, no reboot)"
          prefix = "fpc"
          cmd = "fleet-pull-update"

          [[modules]]
          description = "fleet pull update (reboot)"
          prefix = "fpr"
          cmd = "fleet-pull-update-reboot"

          [[modules]]
          description = "fleet pull update (shutdown)"
          prefix = "fps"
          cmd = "fleet-pull-update-shutdown"
        '';
      };

      # Gated on autoUpdate.enable -- see the option doc above. Unrestricted
      # arguments on nixos-rebuild/switch-to-configuration make this
      # realistically root-equivalent (no way to further narrow it in
      # sudoers), so it's only granted to hosts that actually run this
      # unattended; the manual path uses the sudo -v keep-alive above
      # instead and keeps the normal password-gated sudo.
      security.sudo.extraRules = lib.mkIf config.var.fleet.autoUpdate.enable [{
        users = [ "shot" ];
        commands = [
          { command = "${pkgs.systemd}/bin/systemctl reboot"; options = [ "NOPASSWD" ]; }
          { command = "${pkgs.systemd}/bin/systemctl poweroff"; options = [ "NOPASSWD" ]; }
          # Wildcard on the store path is unavoidable -- it changes per
          # build. Same tradeoff most unattended nixos-rebuild setups
          # (deploy-rs, colmena) accept.
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
          # Always the reboot variant -- an unattended update should come
          # back up on its own; the plain cache-only and shutdown variants
          # are manual-only conveniences.
          ExecStart = "${fleetPullUpdateReboot}/bin/fleet-pull-update-reboot";
        };
      };
    };
  };
}
