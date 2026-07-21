{ config, self, inputs, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.launcher = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    home-manager.users.shot = {
      # Install the required tools
      home.packages = with pkgs; [
        inputs.otter-launcher.packages.${pkgs.stdenv.hostPlatform.system}.default
        systemctl-tui
      ];

      xdg.terminal-exec = {
        enable = true;
        settings.default = [ "foot.desktop" ];
      };

      # Configure otter-launcher
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [general]
        default_module = "search"
        empty_module = "app"
        exec_cmd = "sh -c"

        [[modules]]
        description = "search apps interactively"
        prefix = "search"
        cmd = "fsel --uwsm -d -vv -r -ss \"{}\""
        with_argument = false

        [[modules]]
        description = "launch apps instantly"
        prefix = "app"
        cmd = "uwsm app -t service -- \"{}.desktop\" || uwsm app -t service -- \"{}\""
        with_argument = true

        [[modules]]
        description = "nmtui"
        prefix = "nm"
        cmd = "nmtui"

        [[modules]]
        description = "systemctl-tui"
        prefix = "st"
        cmd = "${pkgs.systemctl-tui}/bin/systemctl-tui"

        [[modules]]
        description = "freeze"
        prefix = "fz"
        cmd = "systemctl --user list-units --type=scope,service --state=running --no-legend | fsel --dmenu | awk '{print $1}' | xargs -r systemctl --user freeze"

        [[modules]]
        description = "thaw"
        prefix = "th"
        cmd = "systemctl --user list-units --type=scope,service --state=running --no-legend | fsel --dmenu | awk '{print $1}' | xargs -r systemctl --user thaw"

        [[modules]]
        description = "calculator"
        prefix = "="
        cmd = "fend"
        with_argument = true

        [[modules]]
        description = "power menu"
        prefix = "po"
        cmd = """
        function power {
        if [[ -n $1 ]]; then
        case $1 in
        "logout") session=`loginctl session-status | head -n 1 | awk '{print $1}'`; loginctl terminate-session $session ;;
        "suspend") systemctl suspend ;;
        "hibernate") systemctl hibernate ;;
        "reboot") systemctl reboot ;;
        "shutdown") systemctl poweroff ;;
        "lock") lock ;;
        esac fi }
        power $(echo -e 'reboot\nshutdown\nlogout\nsuspend\nhibernate\nlock' | fsel --dmenu | tail -1)
        """

        [interface]
        header = "  $USER@$(echo $HOSTNAME)     \u001B[31m\u001B[0m $(free -h | awk 'FNR == 2 {print $3}' | sed 's/i//')\n  "
        list_prefix = "  "
        selection_prefix = "\u001B[31;1m> "
        place_holder = "type & search"
        default_module_message = " \u001B[33mOpen\u001B[0m"
        suggestion_mode = "list"
        suggestion_lines = 4
        prefix_padding = 3
        prefix_color = "\u001B[33m"
        description_color = "\u001B[39m"
        place_holder_color = "\u001B[90m"
        hint_color = "\u001B[90m"
      '';
    };
  };
}
