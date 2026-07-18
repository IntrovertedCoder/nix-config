{ config, self, inputs, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.launcher = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    home-manager.users.shot = {
      # Install the required tools
      home.packages = with pkgs; [
        inputs.otter-launcher.packages.${pkgs.system}.default
      ];

      # Configure otter-launcher
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [general]
        default_module = "search"
        empty_module = "search"
        exec_cmd = "sh -c"

        [[modules]]
        description = "search apps interactively"
        prefix = "search"
        cmd = "fsel -vv -r -ss \"{}\""
        with_argument = false

        [[modules]]
        description = "launch apps instantly"
        prefix = "app"
        cmd = "uwsm app -t service -- \"{}\""
        with_argument = true

        [[modules]]
        description = "nmtui"
        prefix = "nm"
        cmd = "nmtui"

        [interface]
        header = "  $USER@$(echo $HOSTNAME)     \u001B[31m\u001B[0m $(free -h | awk 'FNR == 2 {print $3}' | sed 's/i//')\n  "
        list_prefix = "  "
        selection_prefix = "\u001B[31;1m> "
        place_holder = "type & search"
        default_module_message = " \u001B[33mOpen\u001B[0m"
        suggestion_mode = "list"
        suggestion_lines = 4
        prefix_padding = 3
        prefix_color = "\u001B[33m"
        description_color = "\u001B[39m"
        place_holder_color = "\u001B[90m"
        hint_color = "\u001B[90m"
      '';
    };
  };
}
