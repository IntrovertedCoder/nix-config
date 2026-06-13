{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.starship = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.starship = {
        enable = true;
        enableFishIntegration = true;
        enableBashIntegration = true;
        settings = {
          add_newline = false;

          right_format = "$status $memory_usage $cmd_duration $sudo";

          character = {
            success_symbol = "[➜](#${c.green})";
            error_symbol = "[✗](#${c.red})";
          };

          git_commit = {
            commit_hash_length = 4;
          };

          git_branch = {
            truncation_length = 4;
            truncation_symbol = "";
            ignore_branches = ["master" "main"];
          };

          git_metrics = {
            added_style = "bold #${c.lblue}";
            format = "[+$added]($added_style)/[-$deleted]($deleted_style) ";
          };

          git_status = {
            conflicted = "[=/($count\)](#${c.red})";
            ahead = "[⇡\($count\)](#${c.magenta})";
            behind = "[⇣\($count\)](#${c.lred})";
            diverged = "[⇕\($count\)](#${c.white2})";
            up_to_date = "[✓\($count\)](#${c.blue})";
            untracked = "[?\($count\)](#${c.lmagenta})";
            stashed = "[$\($count\)](#${c.magenta})";
            modified = "[!\($count\)](#${c.yellow})";
            staged = "[+\($count\)](#${c.green})";
            renamed = "[»\($count\)](#${c.orange})";
            deleted = "[✘\($count\)](#${c.lred})";
          };

          python = {
            symbol = "";
          };

          directory = {
            read_only = "";
            format = "[$path](#${c.blue})[$read_only](#${c.red}) ";
            truncation_length = 16;
            truncation_symbol = "…/";
          };

          sudo = {
            format = "[](#${c.orange})";
            disabled = false ;
          };

          cmd_duration = {
            min_time = 500;
            format = "[ $duration](#${c.yellow})" ;
          };

          container = {
            format = "[ \\[$name\\]](#${c.magenta})" ;
          };

          username = {
            format = "[$user](#${c.yellow})";
          };

          hostname = {
            format = " at [$hostname](#${c.magenta}) in ";
            disabled = false ;
          };

          memory_usage = {
            disabled = false;
            threshold = -1;
            format = "[󰍛 $ram](#${c.lgreen})";
          };

          status = {
            symbol = "";
            success_symbol = "";
            not_found_symbol = "";
            sigint_symbol = "";
            not_executable_symbol = "";
            format = "[\($symbol$common_meaning$signal_name$maybe_int\)](#${c.black2})";
            map_symbol = true;
            disabled = false ;
          };
        };
      };
    };
  };
}
