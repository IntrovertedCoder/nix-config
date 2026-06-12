{ self, ... }: {
  flake.nixosModules.eza = { pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      eza
    ];
    environment.shellAliases = {
      ls = "eza --icons $argv";
      la = "eza -a --icons $argv";
      ll = "eza -alhg --icons --octal-permissions $argv";
      lt = "eza --tree --level=2 --icons --group-directories-first $argv";
      tree = "eza --tree --icons=always --color=always --group-directories-first | less -r";
    };
    # programs.fish.functions.tree = {
      # body = "eza --tree --icons=always --color=always --group-directories-first $argv | less -r";
    # };
  };
}
