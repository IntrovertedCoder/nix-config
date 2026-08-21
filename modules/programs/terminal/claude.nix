{ self, inputs, ... }: {
  flake.nixosModules.claude-code = { pkgs, ...}: {
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
      home.packages = with pkgs; [
        claude-code
      ];
    };
  };
}
