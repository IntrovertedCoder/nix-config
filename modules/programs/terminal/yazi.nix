{ config, inputs, ...}:
let
  c = config.var.colors;
in {
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
          starship         = pkgs.yaziPlugins.starship;
        };

        extraPackages = with pkgs; [
          zoxide
          duckdb
          ouch
          rich-cli
        ];

        settings = {
          mgr = {
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
          require("starship"):setup()
        '';
        theme = {
          # : Manager {{{
          mgr = {
            cwd = { fg = "#${c.cyan}"; };

            # Find
            find_keyword  = { fg = "#${c.yellow}"; bold = true; italic = true; underline = true; };
            find_position = { fg = "#${c.magenta}"; bg = "reset"; bold = true; italic = true; };

            # Marker
            marker_copied  = { fg = "#${c.green}"; bg = "#${c.green}"; };
            marker_cut     = { fg = "#${c.red}"; bg = "#${c.red}"; };
            marker_marked  = { fg = "#${c.cyan}"; bg = "#${c.cyan}"; };
            marker_selected = { fg = "#${c.yellow}"; bg = "#${c.yellow}"; };

            # Count
            count_copied   = { fg = "#${c.black}"; bg = "#${c.green}"; };
            count_cut      = { fg = "#${c.black}"; bg = "#${c.red}"; };
            count_selected = { fg = "#${c.black}"; bg = "#${c.yellow}"; };

            # Border
            border_symbol = "│";
            border_style  = { fg = "#${c.grey1}"; };
          };
          # : }}}

          # : Tabs {{{
          tabs = {
            active   = { fg = "#${c.black}"; bg = "#${c.blue}"; bold = true; };
            inactive = { fg = "#${c.blue}"; bg = "#${c.black2}"; };
          };
          # : }}}

          # : Mode {{{
          mode = {
            normal_main = { fg = "#${c.black}"; bg = "#${c.blue}"; bold = true; };
            normal_alt  = { fg = "#${c.blue}"; bg = "#${c.black2}"; };

            # Select mode
            select_main = { fg = "#${c.black}"; bg = "#${c.cyan}"; bold = true; };
            select_alt  = { fg = "#${c.cyan}"; bg = "#${c.black2}"; };

            # Unset mode
            unset_main = { fg = "#${c.black}"; bg = "#${c.lmagenta}"; bold = true; };
            unset_alt  = { fg = "#${c.lmagenta}"; bg = "#${c.black2}"; };
          };
          # : }}}

          # : Status bar {{{
          status = {
            # Permissions
            perm_sep   = { fg = "#${c.grey1}"; };
            perm_type  = { fg = "#${c.blue}"; };
            perm_read  = { fg = "#${c.yellow}"; };
            perm_write = { fg = "#${c.red}"; };
            perm_exec  = { fg = "#${c.green}"; };

            # Progress
            progress_label  = { fg = "#${c.white}"; bold = true; };
            progress_normal = { fg = "#${c.green}"; bg = "#${c.black2}"; };
            progress_error  = { fg = "#${c.yellow}"; bg = "#${c.red}"; };
          };
          # : }}}

          # : Pick {{{
          pick = {
            border   = { fg = "#${c.blue}"; };
            active   = { fg = "#${c.magenta}"; bold = true; };
            inactive = {};
          };
          # : }}}

          # : Input {{{
          input = {
            border   = { fg = "#${c.blue}"; };
            title    = {};
            value    = {};
            selected = { reversed = true; };
          };
          # : }}}

          # : Completion {{{
          cmp = {
            border = { fg = "#${c.blue}"; };
          };
          # : }}}

          # : Tasks {{{
          tasks = {
            border  = { fg = "#${c.blue}"; };
            title   = {};
            hovered = { fg = "#${c.magenta}"; bold = true; };
          };
          # : }}}

          # : Which {{{
          which = {
            mask            = { bg = "#${c.black}"; };
            cand            = { fg = "#${c.cyan}"; };
            rest            = { fg = "#${c.black2}"; };
            desc            = { fg = "#${c.magenta}"; };
            separator       = " -> ";
            separator_style = { fg = "#${c.grey1}"; };
          };
          # : }}}

          # : Help {{{
          help = {
            on      = { fg = "#${c.cyan}"; };
            run     = { fg = "#${c.magenta}"; };
            hovered = { reversed = true; bold = true; };
            footer  = { fg = "#${c.black2}"; bg = "#${c.white}"; };
          };
          # : }}}

          # : Spotter {{{
          spot = {
            border   = { fg = "#${c.blue}"; };
            title    = { fg = "#${c.blue}"; };
            tbl_col  = { fg = "#${c.cyan}"; };
            tbl_cell = { fg = "#${c.magenta}"; bg = "#${c.black2}"; };
          };
          # : }}}

          # : Notification {{{
          notify = {
            title_info  = { fg = "#${c.green}"; };
            title_warn  = { fg = "#${c.yellow}"; };
            title_error = { fg = "#${c.red}"; };
          };
          # : }}}

          # : File-specific styles {{{
          filetype = {
            rules = [
              # Directories must go before the catch-all '*' rule
              { url = "*/"; fg = "#${c.blue}"; }

              # Image
              { mime = "image/*"; fg = "#${c.cyan}"; }
              # Media
              { mime = "{audio,video}/*"; fg = "#${c.yellow}"; }
              # Archive
              { mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}"; fg = "#${c.magenta}"; }
              # Document
              { mime = "application/{pdf,doc,rtf}"; fg = "#${c.green}"; }
              # Virtual file system
              { mime = "vfs/{absent,stale}"; fg = "#${c.grey1}"; }
              
              # Fallback Text
              { url = "*"; fg = "#${c.white}"; }
            ];
          };
          # : }}}

          # : Icons {{{
          icon = {
            dirs = [
              { name = ".config"; text = ""; fg = "#${c.magenta}"; }
              { name = ".git"; text = ""; fg = "#${c.cyan}"; }
              { name = ".github"; text = ""; fg = "#${c.blue}"; }
              { name = ".npm"; text = ""; fg = "#${c.blue}"; }
              { name = "Desktop"; text = ""; fg = "#${c.cyan}"; }
              { name = "Development"; text = ""; fg = "#${c.cyan}"; }
              { name = "Documents"; text = ""; fg = "#${c.cyan}"; }
              { name = "Downloads"; text = ""; fg = "#${c.cyan}"; }
              { name = "Library"; text = ""; fg = "#${c.cyan}"; }
              { name = "Movies"; text = ""; fg = "#${c.cyan}"; }
              { name = "Music"; text = ""; fg = "#${c.cyan}"; }
              { name = "Pictures"; text = ""; fg = "#${c.cyan}"; }
              { name = "Public"; text = ""; fg = "#${c.cyan}"; }
              { name = "Videos"; text = ""; fg = "#${c.cyan}"; }
            ];
            conds = [
              # Special files
              { "if" = "orphan"; text = ""; fg = "#${c.white}"; }
              { "if" = "link"; text = ""; fg = "#${c.grey1}"; }
              { "if" = "block"; text = ""; fg = "#${c.lmagenta}"; }
              { "if" = "char"; text = ""; fg = "#${c.lmagenta}"; }
              { "if" = "fifo"; text = ""; fg = "#${c.lmagenta}"; }
              { "if" = "sock"; text = ""; fg = "#${c.lmagenta}"; }
              { "if" = "sticky"; text = ""; fg = "#${c.lmagenta}"; }
              { "if" = "dummy"; text = ""; fg = "#${c.red}"; }

              # Fallback
              { "if" = "dir"; text = ""; fg = "#${c.blue}"; }
              { "if" = "exec"; text = ""; fg = "#${c.green}"; }
              { "if" = "!dir"; text = ""; fg = "#${c.white}"; }
            ];
          };
          # : }}}
        };
      };
    };
  };
}
