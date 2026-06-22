{ self, inputs, ... }: {
  flake.nixosModules.eza = { pkgs, ...}: {
    imports = [
      self.nixosModules.ls
    ];
    environment.systemPackages = with pkgs; [
      eza
    ];
    environment.shellAliases = {
      ls = "eza --icons";
      la = "eza -a --icons";
      ll = "eza -alhg --icons --octal-permissions";
      lt = "eza --tree --level=2 --icons --group-directories-first";
      tree = "eza --tree --icons=always --color=always --group-directories-first | less -r";
    };
    # programs.fish.functions.tree = {
      # body = "eza --tree --icons=always --color=always --group-directories-first $argv | less -r";
    # };
  };
}
