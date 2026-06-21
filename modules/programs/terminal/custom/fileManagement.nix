{ self, inputs, ... }: {
  flake.nixosModules.fileManagement = { pkgs, ...}: {
    imports = [
    ];
    environment.systemPackages = with pkgs; [
      progress
      xcp
      (writeShellScriptBin "mv" /*bash*/ ''
        # Run mv in the background
        ${pkgs.coreutils}/bin/mv "$@" &
        MV_PID=$!

        sleep 0.2

        # See if mv is still running
        if kill -0 $MV_PID 2>/dev/null; then
            echo -e "\n\033[1;36m✈️ Cross-disk/heavy move detected. Activating progress bar...\033[0m"

            # Run progress in the FOREGROUND, specifically targeting the mv PID.
            # It now has full TTY control and will display beautifully.
            ${pkgs.progress}/bin/progress -w -m -p $MV_PID
        fi

        wait $MV_PID
        EXIT_CODE=$?

        exit $EXIT_CODE
      '')

      (writeShellScriptBin "mvd" /*bash*/ ''
        ${pkgs.rsync}/bin/rsync -aP --remove-source-files "$@"
        if [ $? -eq 0 ]; then
          for arg in "$@"; do
            # If the argument is a directory and it still exists, try to remove it
            if [ -d "$arg" ]; then
              find "$arg" -type d -empty -delete 2>/dev/null
            fi
          done
        fi
      '')
    ];
    environment.shellAliases = {
      cp = "${pkgs.xcp}/bin/xcp";
    };
  };
}
