{ self, inputs, ... }: {
  flake.nixosModules.vmtestOrchestrator = { pkgs, lib, config, ... }: let
    secretsDir = ../../secrets;
    discordWebhookFile = secretsDir + "/discord-webhook.age";
    healthchecksUrlFile = secretsDir + "/healthchecks-ping-url.age";

    haveDiscordSecret = builtins.pathExists discordWebhookFile;
    haveHealthchecksSecret = builtins.pathExists healthchecksUrlFile;
  in {
    imports = [
      inputs.agenix.nixosModules.default
      self.nixosModules.discordNotify
      self.nixosModules.fleetRegistry
    ];

    # The agenix *CLI* (for `agenix -e secrets/foo.age`), distinct from
    # inputs.agenix.nixosModules.default above (which only decrypts at
    # boot). Only vmtest ever edits secrets, so only vmtest needs this.
    environment.systemPackages = [ inputs.agenix.packages.${pkgs.system}.default ];

    # fleet-update.service runs unattended (as `shot`, who's already in
    # `wheel` -- see modules/users/shot.nix) with no TTY and no polkit
    # agent present, so `nh os boot`'s privilege elevation has nothing to
    # authenticate against: plain `sudo` fails immediately (no password
    # can be prompted), and nh's "auto" strategy falls through to `run0`,
    # which needs polkit and fails the same way. This doesn't raise what
    # `shot` can already do (full password-gated sudo) -- it only drops
    # the prompt, and only on vmtest, a disposable dev VM whose whole
    # purpose here is running this unattended. Kept scoped to this module
    # (imported only by vmtest.nix) rather than applied fleet-wide.
    security.sudo.wheelNeedsPassword = false;

    # TODO: once secrets/discord-webhook.age and secrets/healthchecks-ping-url.age
    # exist for real (see secrets.nix and the plan's Sequencing steps 1-2),
    # this block starts wiring them up automatically -- nothing else to change.
    age.secrets =
      lib.optionalAttrs haveDiscordSecret {
        discord-webhook = {
          file = discordWebhookFile;
          owner = "shot";
        };
      }
      // lib.optionalAttrs haveHealthchecksSecret {
        healthchecks-ping-url = {
          file = healthchecksUrlFile;
          owner = "root";
        };
      };

    var.notify.discord.webhookPath =
      lib.mkIf haveDiscordSecret config.age.secrets.discord-webhook.path;

    systemd.timers.fleet-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Thu *-*-* 03:00:00";
        Persistent = true; # catch up if vmtest was off at 03:00
      };
    };

    systemd.services.fleet-update = {
      description = "vmtest: weekly self-update, fleet build/cache-warm, reboot";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "shot";
        WorkingDirectory = "/home/shot/nix-config";
        # /run/wrappers/bin: NixOS's real *setuid* sudo lives only there --
        # pkgs.sudo (were it in runtimeInputs) would be the unprivileged
        # store copy and can never elevate. Without this, nh's elevation
        # detection can't find sudo at all and falls through to run0,
        # which needs polkit and fails with no interactive session present.
        Environment = [
          "HOME=/home/shot"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
        ];
        ExecStart = lib.getExe (pkgs.writeShellApplication {
          name = "fleet-update";
          # openssh: `git fetch`/`push` over the SSH remote shells out to
          # `ssh`, which writeShellApplication's curated PATH otherwise
          # omits -- systemd services get essentially none of the normal
          # interactive PATH, so this has to be explicit.
          runtimeInputs = [ pkgs.git pkgs.nh pkgs.nix pkgs.systemd pkgs.openssh ];
          text = ''
            # Never let a missing/unconfigured secret take the whole run down --
            # see modules/network/discord-notify.nix, this is a no-op until then.
            notify() { command -v notify-discord >/dev/null 2>&1 && notify-discord "$1" || true; }

            cd /home/shot/nix-config

            # vmtest's own SSH host key was already used to decrypt the two
            # secrets above; git needs the *shot* user's ~/.ssh/github key
            # (git.nix) to reach GitHub -- both are independent of this step.
            if ! git fetch origin || ! git merge --ff-only origin/main; then
              notify "vmtest: git pull failed (diverged checkout?) -- aborting this cycle"
              git checkout -- flake.lock
              exit 1
            fi

            # Explicit flake path, not relying on NH_FLAKE: programs.nh.flake
            # only sets that env var via an interactive shell profile, which
            # a systemd service never sources (same class of bug as the
            # missing openssh fix above).
            if ! nh os boot --update -H vmtest /home/shot/nix-config; then
              notify "vmtest: self-update FAILED (see journalctl -u fleet-update)"
              git checkout -- flake.lock
              exit 1
            fi

            # Committed *before* the cache-warm loop below, not after: the
            # seasonal wallpaper (modules/theme/wallpaper-seasonal.nix)
            # picks its default color week from self.lastModifiedDate --
            # the last commit's date -- purely, with no env var/--impure
            # plumbing between vmtest and a follower. That only actually
            # lands on the same week for both sides if this commit (the
            # one a Friday `fleet-pull-update` will pull) already exists
            # *before* the loop below evaluates it -- committing after
            # would warm the cache against last week's commit instead,
            # a cache miss for that one derivation every single cycle.
            if ! git diff --quiet -- flake.lock; then
              git add flake.lock
              git commit -m "flake.lock: automated update $(date -Idate)"
              git push
            fi

            # Warm the cache for the rest of the fleet, and catch host-specific
            # build breakage early. A failure here is per-host and doesn't
            # block the reboot -- it might just mean that host's own config
            # broke, unrelated to this update. (Array form, not a bare
            # word-split loop, so this stays correct -- and shellcheck-clean
            # -- whether var.fleet.hosts has one entry or many.)
            hosts=(${lib.concatMapStringsSep " " lib.escapeShellArg config.var.fleet.hosts})
            for host in "''${hosts[@]}"; do
              if nix build ".#nixosConfigurations.$host.config.system.build.toplevel" --no-link; then
                notify "fleet: $host built OK, cache warmed"
              else
                notify "fleet: build for $host FAILED"
              fi
            done

            # sudo: this script runs as `shot`, not root -- same reason
            # follower.nix's fleet-pull-update needs it for its own final
            # reboot. wheelNeedsPassword=false above covers this already.
            sudo systemctl reboot
          '';
        });
      };
    };

    # Runs on every boot, not just after fleet-update -- the dead-man's-switch
    # needs to reflect "is vmtest alive" unconditionally.
    systemd.services.fleet-boot-confirm = {
      description = "vmtest: boot confirmation heartbeat (healthchecks.io + Discord)";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (pkgs.writeShellApplication {
          name = "fleet-boot-confirm";
          runtimeInputs = [ pkgs.curl pkgs.coreutils pkgs.gnugrep ];
          text = ''
            notify() { command -v notify-discord >/dev/null 2>&1 && notify-discord "$1" || true; }
            ${lib.optionalString haveHealthchecksSecret ''
              curl -sf "$(cat ${config.age.secrets.healthchecks-ping-url.path})" >/dev/null || true
            ''}
            generation="$(readlink /run/current-system | grep -oE '[0-9]+' | tail -1)"
            notify "vmtest booted OK on generation $generation"
          '';
        });
      };
    };
  };
}
