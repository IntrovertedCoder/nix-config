{ self, inputs, ... }: {
  flake.nixosModules.vs = { pkgs, ...}: {
    imports = [
      # self.nixosModules.fd
      # self.nixosModules.fsel
    ];
    environment.systemPackages = with pkgs; [
    ];
    environment.shellAliases = {
      vs = "fd | fsel --dmenu | xargs -r -o vim";
    };
  };
}
