{ self, inputs, ... }: {
  flake.nixosModules.discordNotify = { pkgs, lib, config, ... }: let
    cfg = config.var.notify.discord;
  in {
    options.var.notify.discord.webhookPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing a Discord webhook URL (e.g. an agenix
        secret's `.path`) for the updates channel: what went fine, for the
        record. Null disables the `notify-discord` script entirely --
        callers that want notifications to be optional should just skip
        calling it, or accept it may not exist yet.
      '';
    };

    options.var.notify.discord.urgentWebhookPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Webhook file for the action-required channel, used by
        `notify-discord --urgent`. Null sends those to the updates channel.
      '';
    };

    config = lib.mkIf (cfg.webhookPath != null) {
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "notify-discord";
          runtimeInputs = [ pkgs.curl pkgs.jq ];
          text = /* bash */ ''
            # notify-discord [--urgent] <message>
            webhookFile=${lib.escapeShellArg cfg.webhookPath}
            if [ "''${1:-}" = --urgent ]; then
              shift
              ${lib.optionalString (cfg.urgentWebhookPath != null)
                "webhookFile=${lib.escapeShellArg cfg.urgentWebhookPath}"}
            fi
            webhook="$(cat "$webhookFile")"
            message="''${1:?usage: notify-discord [--urgent] <message>}"
            payload="$(jq -n --arg c "$message" '{content: $c}')"
            curl -sf -H "Content-Type: application/json" -d "$payload" "$webhook" >/dev/null
          '';
        })
      ];
    };
  };
}
