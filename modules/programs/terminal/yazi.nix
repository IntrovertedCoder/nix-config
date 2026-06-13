{ self, inputs, ... }: {
  flake.nixosModules.yazi = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      programs.yazi = {
        enable = true;
        enableFishIntegration = true;
        shellWrapperName = "yy";

        plugins = {
          duckdb           = pkgs.yaziPlugins.duckdb;
          ouch             = pkgs.yaziPlugins.ouch;
          rich-preview     = pkgs.yaziPlugins.rich-preview;
          # starship         = pkgs.yaziPlugins.starship;
        };

        extraPackages = with pkgs; [
          zoxide
          duckdb
          ouch
          rich-cli
        ];

        settings = {
          manager = {
            sort_by       = "natural";
            sort_fallback = "alphabetical";
            linemode      = "permissions";
            show_hidden   = true;
          };

          plugin = {
            prepend_previewers = [
              # Archive extraction previews with ouch
              { mime = "application/x-7z-compressed"; run = "ouch"; }
              { mime = "application/x-tar"; run = "ouch"; }
              { mime = "application/x-bzip2"; run = "ouch"; }
              { mime = "application/x-gzip"; run = "ouch"; }
              { mime = "application/zip"; run = "ouch"; }
              { mime = "application/x-rar"; run = "ouch"; }

              # Tabular / Data file views with DuckDB
              { url = "*.csv"; run = "duckdb"; }
              { url = "*.tsv"; run = "duckdb"; }
              { url = "*.parquet"; run = "duckdb"; }

              # Syntax highlighted document styling with rich-preview
              { url = "*.md"; run = "rich-preview"; }
              { url = "*.json"; run = "rich-preview"; }
            ];
          };
        };

        keymap = {
          mgr.prepend_keymap = [
            { on = [ "g" "n" ]; run = "cd ~/nix-config"; desc = "Go to Nixos config"; }
            { on = [ "g" "d" ]; run = "cd ~/Downloads";  desc = "Go to Downloads"; }
            { on = [ "r" "b" ]; run = "shell 'nh os switch' --block";    desc = "Rebuild nix system"; }
            { on = [ "v" "s" ]; run = "shell 'vs' --block";    desc = "Find files to edit with vim"; }
          ];
        };

        initLua = /* lua */ ''
          -- require("starship"):setup()
        '';
      };
    };
  };
}
