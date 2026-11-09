{ self, inputs, ... }: {
  flake.nixosModules.claude-code = { config, pkgs, ...}:
  let
    # DELETE this block (and use plain pkgs.claude-code below) once nixpkgs
    # 26.05 carries claude-code >= 2.1.225; it is stuck on 2.1.223, which
    # predates the current models. unstable is on 2.1.295.
    # legacyPackages can't be used here: that pkgs instance has no unfree
    # config of its own, so reuse the predicate custom.allowedUnfree builds.
    unstable = import inputs.unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfreePredicate = config.nixpkgs.config.allowUnfreePredicate;
    };
  in {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];

    preservation.preserveAt."/persistent" = {
      users.shot = {
        directories = [
          ".claude"
        ];
        files = [
          ".claude.json"
        ];
      };
    };

    # nixpkgs' claude-code is an unfree binary redistribution (fetched
    # straight from downloads.claude.ai), same as zoom-us/teams-for-linux.
    custom.allowedUnfree = [
      "claude-code"
    ];

    home-manager.users.shot = {
      home.packages = [
        unstable.claude-code
      ];
    };
  };
}
