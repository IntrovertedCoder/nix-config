{ self, inputs, ... }: {
  flake.nixosModules.git = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.git.enable = true;

    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
      programs.git = {
        enable = true;
        delta.enable = true;
        userEmail = "NATrotinc@gmail.com";
        userName = "IntrovertedCoder";
      };
    };
  };
}
