{ self, inputs, ... }: {
  flake.nixosModules.gammastep = { pkgs, ...}: 
  let
    gamma-control = pkgs.writeShellApplication {
      name = "gamma-control";
      runtimeInputs = [ pkgs.gammastep pkgs.procps pkgs.bc ];
      text = /* bash */ ''
        STATE_FILE="/tmp/gamma_state"
        PID_FILE="/tmp/gamma_pid"
        # Configuration
        TEMP_STEP=500
        BRIGHT_STEP=0.1
        MAX_TEMP=10000
        MIN_TEMP=1500
        MAX_BRIGHT=1.0
        MIN_BRIGHT=0.2

        # Initialize state if missing
        if [ ! -f "$STATE_FILE" ]; then
          echo "6500 1.0" > "$STATE_FILE"
        fi

        read -r TEMP BRIGHT < "$STATE_FILE"

        case "$1" in
          temp-up)
            TEMP=$((TEMP + TEMP_STEP))
            [ "$TEMP" -gt "$MAX_TEMP" ] && TEMP=$MAX_TEMP
            ;;
          temp-down)
            TEMP=$((TEMP - TEMP_STEP))
            [ "$TEMP" -lt "$MIN_TEMP" ] && TEMP=$MIN_TEMP
            ;;
          bright-up)
            BRIGHT=$(echo "$BRIGHT + $BRIGHT_STEP" | bc)
            if [ "$(echo "$BRIGHT > $MAX_BRIGHT" | bc)" -eq 1 ]; then BRIGHT=$MAX_BRIGHT; fi
            ;;
          bright-down)
            BRIGHT=$(echo "$BRIGHT - $BRIGHT_STEP" | bc)
            if [ "$(echo "$BRIGHT < $MIN_BRIGHT" | bc)" -eq 1 ]; then BRIGHT=$MIN_BRIGHT; fi
            ;;
          reset)
            TEMP=6500
            BRIGHT=1.0
            ;;
          *)
            echo "Usage: gamma-control {temp-up|temp-down|bright-up|bright-down|reset}"
            exit 1
            ;;
        esac

        echo "$TEMP $BRIGHT" > "$STATE_FILE"

        # Kill the exact previous instance
        if [ -f "$PID_FILE" ]; then
          OLD_PID=$(cat "$PID_FILE")
          if ps -p "$OLD_PID" > /dev/null 2>&1; then
            kill "$OLD_PID" || true
            # Wait up to 1 second for it to gracefully release the Wayland protocol
            for _ in $(seq 1 10); do
              if ! ps -p "$OLD_PID" > /dev/null 2>&1; then
                break
              fi
              sleep 0.1
            done

            # Force kill if hanging
            if ps -p "$OLD_PID" > /dev/null 2>&1; then
              kill -9 "$OLD_PID" || true
            fi
          fi
        else
          # Fallback catch-all for orphaned processes
          pkill -f "gammastep" || true
        fi

        # If returning to default, clear the PID file and exit (leaves no gammastep running)
        if [ "$TEMP" -eq 6500 ] && [ "$(echo "$BRIGHT == 1.0" | bc)" -eq 1 ]; then
          rm -f "$PID_FILE"
          exit 0
        fi
        # Start gammastep manually (-O) and disable fading (-r)
        gammastep -O "$TEMP" -b "$BRIGHT" -r > /dev/null 2>&1 &
        # Save the exact Process ID of the backgrounded task
        echo "$!" > "$PID_FILE"
      '';
    };
  in {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    environment.systemPackages = with pkgs; [
    ];

    home-manager.users.shot = {
      wayland.windowManager.mango.settings.bind = [
        "ALT,Up,spawn_shell,gamma-control bright-up"
        "ALT,Down,spawn_shell,gamma-control bright-down"
        "ALT,Right,spawn_shell,gamma-control temp-up"
        "ALT,Left,spawn_shell,gamma-control temp-down"
        "ALT,Home,spawn_shell,gamma-control reset"
      ];
      home.packages = [
        gamma-control
      ];

      services.gammastep.enable = false;
    };
  };
}
