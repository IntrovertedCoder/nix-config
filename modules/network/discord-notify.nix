{ self, inputs, ... }: {
  flake.nixosModules.discordNotify = { pkgs, lib, config, ... }: {
    options.var.notify.discord.webhookPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing a Discord webhook URL (e.g. an agenix
        secret's `.path`). Null disables the `notify-discord` script
        entirely -- callers that want notifications to be optional should
        just skip calling it, or accept it may not exist yet.
      '';
    };

    config = lib.mkIf (config.var.notify.discord.webhookPath != null) {
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "notify-discord";
          runtimeInputs = [ pkgs.curl pkgs.jq ];
          text = ''
            webhook="$(cat ${lib.escapeShellArg config.var.notify.discord.webhookPath})"
            message="''${1:?usage: notify-discord <message>}"
            payload="$(jq -n --arg c "$message" '{content: $c}')"
            curl -sf -H "Content-Type: application/json" -d "$payload" "$webhook" >/dev/null
          '';
        })
      ];
    };
  };
}
