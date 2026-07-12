{ self, inputs, ... }: {
  flake.nixosModules.ex = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      unar
      (writeShellScriptBin "ex" /*bash*/ ''
        unar -d "$@"
      '')

    ];
  };
}
