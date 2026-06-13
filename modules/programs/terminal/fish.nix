{ config, inputs, ...}:
let
  c = config.var.colors;
in {
  flake.nixosModules.fish = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    programs.fish.enable = true;
    users.users.shot.shell = pkgs.fish;
    home-manager.users.shot = {
      programs.fish = {
        enable = true;
        interactiveShellInit = /* fish */ ''
          # Custom theme {{{
            # Base16 Fish Theme - Synced perfectly with your mini.base16 schema
            set -g fish_color_normal ${c.white}          # base05: Default text
            set -g fish_color_command ${c.magenta}       # base0D: Commands and Functions
            set -g fish_color_keyword ${c.cyan}          # base0E: Control flow keywords (if/else)
            set -g fish_color_quote ${c.green}           # base0B: Strings and quotes
            set -g fish_color_redirection ${c.blue}      # base0C: IO streams and redirects (>, |)
            set -g fish_color_end ${c.cyan}              # base0E: Statement separators (;)
            set -g fish_color_error ${c.red}             # base08: Command errors
            set -g fish_color_param ${c.white2}          # base04: Command arguments/parameters
            set -g fish_color_comment ${c.grey3}         # base03: Code comments
            set -g fish_color_operator ${c.blue}         # base0C: Logic operators
            set -g fish_color_escape ${c.orange}         # base09: Escape characters (\n, \t)
            set -g fish_color_autosuggestion ${c.grey2}   # base02: Dimmed history suggestions

            # Selection and Search UI
            set -g fish_color_selection --background=${c.black2}     # base01: Terminal text selection
            set -g fish_color_search_match --background=${c.black2}  # base01: Interactive search highlights

            # Tab-Completion Pager Menu
            set -g fish_pager_color_prefix ${c.cyan} --bold          # base0E: Matching character prefix
            set -g fish_pager_color_completion ${c.white}            # base05: Unselected menu items
            set -g fish_pager_color_description ${c.grey3}           # base03: Right-side help descriptions
            set -g fish_pager_color_progress ${c.white} --background=${c.magenta} # Selected item row indicator
          # }}}

          # # Custom prompt {{{
          #   function fish_prompt
          #     set -g __fish_git_prompt_show_informative_status 1
          #     set -g __fish_git_prompt_color_branch ${c.magenta} --bold
          #
          #     set -g __fish_git_prompt_char_untrackedfiles "…"
          #     set -g __fish_git_prompt_color_untrackedfiles ${c.red}
          #
          #     set -g __fish_git_prompt_char_stagedstate "●"
          #     set -g __fish_git_prompt_color_stagedstate ${c.green}
          #
          #     set -g __fish_git_prompt_char_dirtystate "+"
          #     set -g __fish_git_prompt_color_dirtystate ${c.orange}
          #
          #     set -g __fish_git_prompt_char_cleanstate ""
          #     set -g __fish_git_prompt_color_cleanstate ${c.yellow}
          #
          #     set -g __fish_git_prompt_char_upstream_ahead "↑"
          #     set -g __fish_git_prompt_char_upstream_behind "↓"
          #     set -g __fish_git_prompt_char_upstream_equal "="
          #
          #     if test -n "$SSH_TTY"
          #         echo -n (set_color ${c.yellow})(prompt_hostname)' '
          #     end
          #
          #     echo -n (set_color ${c.grey2})(prompt_pwd)
          #
          #     set_color -o
          #     if test "$USER" = 'root'
          #         printf '%s' (set_color ${c.white})('__fish_git_prompt')
          #         echo -n (set_color ${c.blue})' # '
          #     else
          #         printf '%s' (set_color ${c.white})('__fish_git_prompt')
          #         echo -n (set_color ${c.red})' $ '
          #     end
          #     set_color normal
          #   end
          # # }}}


          # Custom keybinds {{{
            bind f2 __fish_prepend_sudo
            bind f3 edit_command_buffer
          # }}}

          # Start text {{{
            function fish_greeting
              function center
                set termwidth (tput cols)
                awk -v termwidth=$termwidth '{ pad=(termwidth - length($0))/2; printf "%*s%s\n", pad, "", $0 }'
              end
              if status is-interactive
                set host (hostname | sed 's/\b\(.\)/\u\1/g')
                set username (whoami | sed 's/\b\(.\)/\u\1/g')
                begin
                  ${pkgs.figlet}/bin/figlet "Welcome     $username" | center
                  ${pkgs.figlet}/bin/figlet "To     $host" | center
                end | ${pkgs.lolcat}/bin/lolcat
              end
            end
          # }}}

        '';

      };
    };
  };
}
