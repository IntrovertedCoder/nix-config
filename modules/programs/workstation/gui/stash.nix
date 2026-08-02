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
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Clipboard history"
        prefix = "ch"
        cmd = "stash list | fsel --dmenu | stash decode > /tmp/wl-copy-data && uwsm app -t service -- sh -c 'wl-copy < /tmp/wl-copy-data'"
      '';
      home.packages = with pkgs; [
      ];
    };
  };
}
