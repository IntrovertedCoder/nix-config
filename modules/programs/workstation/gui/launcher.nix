{ config, self, inputs, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.launcher = { pkgs, config, ...}: {
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
        description = "calculator"
        prefix = "="
        cmd = "fend"
        with_argument = true

        [[modules]]
        description = "calendar"
        prefix = "cal"
        cmd = "cal -n 9 -S -w --color=always | less"
        with_argument = true

        [[modules]]
        description = "calendar current year"
        prefix = "calcy"
        cmd = "cal -y -w --color=always | less"
        with_argument = true

        [[modules]]
        description = "calendar next year"
        prefix = "calny"
        cmd = "cal -Y -w --color=always | less"
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
        "lock") setsid -f ${config.var.lockCommand} >/dev/null 2>&1 ;;
        esac fi }
        power $(echo -e 'reboot\nshutdown\nlogout\nsuspend\nhibernate\nlock' | fsel --dmenu | tail -1)
        """

        [[modules]]
        description = "Run shell command (Background)"
        prefix = "<"
        # This runs silently in the background. Perfect for GUI tools like: $ , baobab
        cmd = "uwsm app -t service -- sh -c '{}'"
        with_argument = true

        [[modules]]
        description = "Run shell command (Foreground)"
        prefix = ">"
        # This opens a new foot window to run the command. Perfect for CLI tools like: > , htop
        # The 'read' command at the end ensures the terminal stays open if the command throws an error.
        cmd = "uwsm app -t service -- foot -e sh -c '{}; echo \"\n[Process Finished - Press Enter to close]\"; read'"
        with_argument = true

        [interface]
        header = "$(${pkgs.writeShellScript "otter-header" ''
          # 1. Helper function to convert Hex to TrueColor ANSI
          hex_to_ansi() {
            local hex=$1
            # Bash printf converts 0x.. to decimal RGB values automatically
            printf "\033[38;2;%d;%d;%dm" 0x''${hex:0:2} 0x''${hex:2:2} 0x''${hex:4:2}
          }

          # 2. Inject Nix colors into Bash variables
          C_RED=$(hex_to_ansi "${c.red}")
          C_GREEN=$(hex_to_ansi "${c.green}")
          C_CYAN=$(hex_to_ansi "${c.cyan}")
          C_BLUE=$(hex_to_ansi "${c.blue}")
          C_MAG=$(hex_to_ansi "${c.magenta}")
          C_RESET="\033[0m"

          # 3. Define total header width
          WIDTH=78

          # 4. Build the Left Module
          LEFT="  $USER@$HOSTNAME   $(date +"%a %y %b %+0e")"

          # 5. Build the Center Module
          CENTER="$(date +%H:%M)"

          # 6. Build the Right Modules
          RAM_VAL=$(free -m | awk '/Mem:/ {printf "%d%%", $3/$2 * 100}')
          RAM="''${C_RED}''${C_RESET} $RAM_VAL"

          if ${pkgs.tailscale}/bin/tailscale status 2>/dev/null | grep -q "stopped"; then
            TS="''${C_CYAN}TS''${C_RESET} ''${C_RED}''${C_RESET}"
          else
            TS="''${C_CYAN}TS''${C_RESET} ''${C_GREEN}''${C_RESET}"
          fi

          if systemctl --user is-active --quiet suspend-block; then
            SL="''${C_MAG}''${C_RESET}"
          else
            SL=""
          fi

          if bluetoothctl show | grep -q 'Powered: yes'; then
            BT="''${C_BLUE}''${C_RESET}"
          else
            BT=""
          fi

          BAT=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
          if [ -n "$BAT" ]; then
            BAT_STR="  ''${C_GREEN}''${C_RESET} $BAT%"
          else
            BAT_STR=""
          fi

          RIGHT="$RAM   $TS$BAT_STR $BT $SL \n"

          # 7. Measure visible lengths (stripping ANSI color codes)
          STRIP_ANSI="s/\x1B\[[0-9;]*[a-zA-Z]//g"
          LEN_L=$(echo -ne "$LEFT" | sed -E "$STRIP_ANSI" | wc -m)
          LEN_C=$(echo -ne "$CENTER" | sed -E "$STRIP_ANSI" | wc -m)
          LEN_R=$(echo -ne "$RIGHT" | sed -E "$STRIP_ANSI" | wc -m)

          # 8. Calculate dynamic spacing
          PAD_L=$(( (WIDTH / 2) - (LEN_C / 2) - LEN_L ))
          PAD_R=$(( WIDTH - LEN_L - PAD_L - LEN_C - LEN_R ))

          [ $PAD_L -lt 1 ] && PAD_L=1
          [ $PAD_R -lt 1 ] && PAD_R=1

          SPACES_L=$(printf "%*s" $PAD_L "")
          SPACES_R=$(printf "%*s" $PAD_R "")

          # 9. Output the perfectly aligned and colored string
          echo -e "$LEFT$SPACES_L$CENTER$SPACES_R$RIGHT $ "
        ''})"
        list_prefix = "  "
        selection_prefix = "\u001B[31;1m> "
        place_holder = "type & search"
        default_module_message = " \u001B[33mOpen\u001B[0m"
        suggestion_mode = "list"
        suggestion_lines = 20
        prefix_padding = 3
        prefix_color = "\u001B[33m"
        description_color = "\u001B[39m"
        place_holder_color = "\u001B[90m"
        hint_color = "\u001B[90m"
      '';
      wayland.windowManager.mango.settings.bind = [
        "ALT,d,spawn,uwsm app -- foot -a launcher -e otter-launcher"
      ];
    };
  };
}
