{ ... }: {
  perSystem = { pkgs, lib, ... }: let
    cluster = import ./_lib.nix { inherit pkgs lib; };
  in lib.mkIf pkgs.stdenv.isLinux {
    packages.cluster-check-access = cluster.mkApp {
      name = "cluster-check-access";
      text = /* bash */ ''
        # Check the nodes can reach each other over mesh SSH (what the cluster
        # tool and every bootstrap app need), and report Tailscale:
        #
        #   nix run .#cluster-check-access
        require_access
      '';
    };
  };
}
