{ inputs, ... }: {
  # Clipboard history, picked from the launcher ("ch"). cliphist replaced
  # stash-clipboard (an unstable-only package) on 2026-11-09, when stash
  # stopped building there.
  flake.nixosModules.cliphist = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    environment.systemPackages = with pkgs; [
      wl-clipboard-rs
    ];

    home-manager.users.shot = {
      services.cliphist.enable = true;
      xdg.configFile."otter-launcher/config.toml".text = /*toml*/ ''
        [[modules]]
        description = "Clipboard history"
        prefix = "ch"
        cmd = "cliphist list | fsel --dmenu | cliphist decode > /tmp/wl-copy-data && uwsm app -t service -- sh -c 'wl-copy < /tmp/wl-copy-data'"
      '';
      services.wl-clip-persist = {
        enable = true;
      };
    };
  };
}
