{ config, inputs, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.tealdeer = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
        (writeShellScriptBin "tldr" /* bash */ ''
          TEALDEER="${pkgs.tealdeer}/bin/tldr"
          CACHE_DIR="$HOME/.cache/tealdeer/tldr-pages"

          # Conditional logic: Update if missing or older than 7 days
          if [ ! -d "$CACHE_DIR" ] || [ -n "$(find "$CACHE_DIR" -maxdepth 0 -mtime +7)" ]; then
            $TEALDEER --update &> /dev/null
          fi

          # Execute the actual tldr binary
          exec $TEALDEER "$@"
        '')
      ];
      xdg.configFile."tealdeer/config.toml".text = /* toml */ ''
        [display]
        compact = true

        [style.command_name.foreground.rgb]
        r = ${toString c.bluerd}
        g = ${toString c.bluegd}
        b = ${toString c.bluebd}

        [style.description.foreground.rgb]
        r = ${toString c.whiterd}
        g = ${toString c.whitegd}
        b = ${toString c.whitebd}

        [style.example_code.foreground.rgb]
        r = ${toString c.magentard}
        g = ${toString c.magentagd}
        b = ${toString c.magentabd}

        [style.example_text.foreground.rgb]
        r = ${toString c.greenrd}
        g = ${toString c.greengd}
        b = ${toString c.greenbd}

        [style.example_variable.foreground.rgb]
        r = ${toString c.cyanrd}
        g = ${toString c.cyangd}
        b = ${toString c.cyanbd}

        [updates]
        auto_update = false
      '';
    };
  };
}
