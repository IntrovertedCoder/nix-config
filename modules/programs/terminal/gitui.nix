{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.gitui = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      (pkgs.writeShellScriptBin "lg" ''
        eval "$(${pkgs.openssh}/bin/ssh-agent -s)" > /dev/null
        trap 'kill "$SSH_AGENT_PID"' EXIT INT TERM > /dev/null
        ${pkgs.openssh}/bin/ssh-add ~/.ssh/github 2> /dev/null
        ${pkgs.gitui}/bin/gitui
      '')
      ];
      programs.gitui = {
        enable = true;
        keyConfig = /* ron */ ''
          (
            open_help: Some(( code: F(1), modifiers: "")),

            move_left: Some(( code: Char('h'), modifiers: "")),
            move_right: Some(( code: Char('l'), modifiers: "")),
            move_up: Some(( code: Char('k'), modifiers: "")),
            move_down: Some(( code: Char('j'), modifiers: "")),

            popup_up: Some(( code: Char('p'), modifiers: "CONTROL")),
            popup_down: Some(( code: Char('n'), modifiers: "CONTROL")),
            page_up: Some(( code: Char('b'), modifiers: "CONTROL")),
            page_down: Some(( code: Char('f'), modifiers: "CONTROL")),
            home: Some(( code: Char('g'), modifiers: "")),
            end: Some(( code: Char('G'), modifiers: "SHIFT")),
            shift_up: Some(( code: Char('K'), modifiers: "SHIFT")),
            shift_down: Some(( code: Char('J'), modifiers: "SHIFT")),

            edit_file: Some(( code: Char('I'), modifiers: "SHIFT")),

            status_reset_item: Some(( code: Char('U'), modifiers: "SHIFT")),

            diff_reset_lines: Some(( code: Char('u'), modifiers: "")),
            diff_stage_lines: Some(( code: Char('s'), modifiers: "")),

            stashing_save: Some(( code: Char('w'), modifiers: "")),
            stashing_toggle_index: Some(( code: Char('m'), modifiers: "")),

            stash_open: Some(( code: Char('l'), modifiers: "")),

            abort_merge: Some(( code: Char('M'), modifiers: "SHIFT")),
          )
        '';

        theme = /* ron */ ''
          (
            selected_tab: Some("Reset"),
            command_fg: Some("#${c.white}"),
            selection_bg: Some("#${c.blue}"),
            selection_fg: Some("#${c.white}"),
            cmdbar_bg: Some("#${c.blue}"),
            cmdbar_extra_lines_bg: Some("#${c.blue}"),
            disabled_fg: Some("#${c.grey2}"),
            diff_line_add: Some("#${c.green}"),
            diff_line_delete: Some("#${c.red}"),
            diff_file_added: Some("#${c.lgreen}"),
            diff_file_removed: Some("#${c.lred}"),
            diff_file_moved: Some("#${c.lmagenta}"),
            diff_file_modified:  Some("#${c.yellow}"),
            commit_hash: Some("#${c.magenta}"),
            commit_time: Some("#${c.lcyan}"),
            commit_author: Some("#${c.green}"),
            danger_fg: Some("#${c.red}"),
            push_gauge_bg: Some("#${c.blue}"),
            push_gauge_fg: Some("Reset"),
            tag_fg: Some("#${c.lmagenta}"),
            branch_fg: Some("#${c.lyellow}"),
          )
        '';
      };
    };
  };
}
