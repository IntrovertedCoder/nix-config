{ self, inputs, ... }: {
  flake.nixosModules.vs = { pkgs, ...}: {
    imports = [
      # self.nixosModules.fd
      # self.nixosModules.fsel
    ];
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "vs" ''
        fd -t f | fsel --dmenu | xargs -r -o vim
      '')
    ];
  };
}
