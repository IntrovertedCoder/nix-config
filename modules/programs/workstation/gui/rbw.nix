{ self, inputs, ... }: {
  flake.nixosModules.rbw = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    preservation.preserveAt."/persistent" = {
      users.shot = {
        files = [
          ".local/share/rbw/device_id"
        ];
      };
    };
    home-manager.users.shot = {
      home.packages = with pkgs; [
        rbw
        wtype
        pinentry-gnome3
      ];
      xdg.configFile."rbw/config.json".text = /*json*/ ''
      {"email":"natrotnic@gmail.com","sso_id":null,"base_url":null,"identity_url":null,"ui_url":null,"notifications_url":null,"lock_timeout":300,"sync_interval":3600,"pinentry":"pinentry","client_cert_path":null}
      '';
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Bitwarden: Lock Vault"
        prefix = "bwl"
        cmd = "${pkgs.writeShellScript "bw-lock" ''
          ${pkgs.rbw}/bin/rbw lock
          ${pkgs.libnotify}/bin/notify-send -u low "Bitwarden" "Vault locked successfully."
        ''}"

        [[modules]]
        description = "Bitwarden: Auto-type Password"
        prefix = "bwp"
        cmd = "${pkgs.writeShellScript "bw-pass" ''
          data=$(${pkgs.rbw}/bin/rbw ls --fields=id,name,user)
          selection=$(printf "%s\n" "$data" | awk -F'\t' '{ if ($3 != "") print $2 "  (" $3 ")"; else print $2 }' | fsel --dmenu)

          if [ -n "$selection" ]; then
            id=$(printf "%s\n" "$data" | awk -F'\t' -v sel="$selection" '{ if ($3 != "") str=$2 "  (" $3 ")"; else str=$2; if (str == sel) { print $1; exit } }')
            if [ -n "$id" ]; then
              pass=$(${pkgs.rbw}/bin/rbw get "$id")
              if [ -n "$pass" ]; then
                printf "%s" "$pass" | ${pkgs.wl-clipboard}/bin/wl-copy
                ${pkgs.libnotify}/bin/notify-send -u low "Bitwarden" "Password copied. Auto-typing in 2s..."
                sleep 2
                printf "%s" "$pass" | ${pkgs.wtype}/bin/wtype -
              fi
            fi
          fi
        ''}"

        [[modules]]
        description = "Bitwarden: Auto-type Username"
        prefix = "bwu"
        cmd = "${pkgs.writeShellScript "bw-user" ''
          data=$(${pkgs.rbw}/bin/rbw ls --fields=id,name,user)
          selection=$(printf "%s\n" "$data" | awk -F'\t' '{ if ($3 != "") print $2 "  (" $3 ")"; else print $2 }' | fsel --dmenu)

          if [ -n "$selection" ]; then
            user=$(printf "%s\n" "$data" | awk -F'\t' -v sel="$selection" '{ if ($3 != "") str=$2 "  (" $3 ")"; else str=$2; if (str == sel) { print $3; exit } }')
            if [ -n "$user" ]; then
              printf "%s" "$user" | ${pkgs.wl-clipboard}/bin/wl-copy
              ${pkgs.libnotify}/bin/notify-send -u low "Bitwarden" "Username copied. Auto-typing in 2s..."
              sleep 2
              printf "%s" "$user" | ${pkgs.wtype}/bin/wtype -
            else
              ${pkgs.libnotify}/bin/notify-send -u normal "Bitwarden" "No username found for this entry."
            fi
          fi
        ''}"

        [[modules]]
        description = "Bitwarden: Auto-type TOTP (2FA)"
        prefix = "bwt"
        cmd = "${pkgs.writeShellScript "bw-totp" ''
          data=$(${pkgs.rbw}/bin/rbw ls --fields=id,name,user)
          selection=$(printf "%s\n" "$data" | awk -F'\t' '{ if ($3 != "") print $2 "  (" $3 ")"; else print $2 }' | fsel --dmenu)

          if [ -n "$selection" ]; then
            id=$(printf "%s\n" "$data" | awk -F'\t' -v sel="$selection" '{ if ($3 != "") str=$2 "  (" $3 ")"; else str=$2; if (str == sel) { print $1; exit } }')
            if [ -n "$id" ]; then
              code=$(${pkgs.rbw}/bin/rbw code "$id")
              if [ -n "$code" ]; then
                printf "%s" "$code" | ${pkgs.wl-clipboard}/bin/wl-copy
                ${pkgs.libnotify}/bin/notify-send -u low "Bitwarden" "TOTP copied. Auto-typing in 2s..."
                sleep 2
                printf "%s" "$code" | ${pkgs.wtype}/bin/wtype -
              else
                ${pkgs.libnotify}/bin/notify-send -u normal "Bitwarden" "No TOTP found for this entry."
              fi
            fi
          fi
        ''}"

        [[modules]]
        description = "Bitwarden: Auto Login (User -> Tab -> Pass) + 2FA"
        prefix = "bwa"
        cmd = "${pkgs.writeShellScript "bw-auto" ''
          data=$(${pkgs.rbw}/bin/rbw ls --fields=id,name,user)
          selection=$(printf "%s\n" "$data" | awk -F'\t' '{ if ($3 != "") print $2 "  (" $3 ")"; else print $2 }' | fsel --dmenu)

          if [ -n "$selection" ]; then
            # Extract both the UUID and the Username at once using awk
            id_user=$(printf "%s\n" "$data" | awk -F'\t' -v sel="$selection" '{ if ($3 != "") str=$2 "  (" $3 ")"; else str=$2; if (str == sel) { print $1 "\t" $3; exit } }')

            id=$(printf "%s" "$id_user" | awk -F'\t' '{print $1}')
            user=$(printf "%s" "$id_user" | awk -F'\t' '{print $2}')

            if [ -n "$id" ]; then
              pass=$(${pkgs.rbw}/bin/rbw get "$id")
              # Attempt to get the 2FA token (silences error if none exists)
              totp=$(${pkgs.rbw}/bin/rbw code "$id" 2>/dev/null) 

              if [ -n "$user" ] && [ -n "$pass" ]; then
                
                # Check if a 2FA token was found, copy it, and notify
                if [ -n "$totp" ]; then
                  printf "%s" "$totp" | ${pkgs.wl-clipboard}/bin/wl-copy
                  ${pkgs.libnotify}/bin/notify-send -u low "Bitwarden" "Auto-logging in 2s...\n2FA copied to clipboard!"
                else
                  ${pkgs.libnotify}/bin/notify-send -u low "Bitwarden" "Auto-logging in 2s..."
                fi

                sleep 2

                # Type Username -> Tab -> Password -> Enter
                printf "%s" "$user" | ${pkgs.wtype}/bin/wtype -
                sleep 0.2
                ${pkgs.wtype}/bin/wtype -k Tab
                sleep 0.2
                printf "%s" "$pass" | ${pkgs.wtype}/bin/wtype -
                sleep 0.2
                ${pkgs.wtype}/bin/wtype -k Return
              else
                ${pkgs.libnotify}/bin/notify-send -u normal "Bitwarden" "Missing username or password for this entry."
              fi
            fi
          fi
        ''}"
      '';
    };
  };
}
