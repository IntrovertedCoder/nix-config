{ self, inputs, ... }: {
  flake.nixosModules.doggo = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
      doggo
      (writeShellScriptBin "dogs" /*bash*/ ''
        doggo --short "$@"
      '')
      (writeShellScriptBin "dogprop" /*bash*/ ''
        DOMAIN=""
        for arg in "$@"; do
          if [[ "$arg" != -* ]]; then
            DOMAIN="$arg"
            break
          fi
        done

        AUTH_NS=""
        if [ -n "$DOMAIN" ]; then
          RAW_NS=$(doggo "$DOMAIN" NS --short 2>/dev/null | head -n 1)
          if [ -n "$RAW_NS" ]; then
            AUTH_NS="@$RAW_NS"
          fi
        fi

        doggo "$@"
        doggo "$@" @8.8.8.8
        doggo "$@" @9.9.9.9
        doggo "$@" @1.1.1.1
        doggo "$@" $AUTH_NS
      '')
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];
    };
  };
}
