{ self, inputs, ... }: {
  flake.nixosModules.stash-clip = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      # DELETE this line when moving to 26.11:
      "${inputs.unstable}/nixos/modules/services/misc/stash-clipboard.nix"
    ];

    services.stash-clipboard.enable = true;

    # DELETE this line when moving to 26.11:
    services.stash-clipboard.package = inputs.unstable.legacyPackages.${pkgs.system}.stash-clipboard;

    environment.systemPackages = with pkgs; [
      # DELETE this line when moving to 26.11:
      inputs.unstable.legacyPackages.${pkgs.system}.stash-clipboard
      # stash-clipboard
      wl-clipboard-rs
    ];

    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
