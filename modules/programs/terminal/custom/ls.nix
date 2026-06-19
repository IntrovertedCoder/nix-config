{ self, inputs, ... }: let
  customIgnores = [
    ".git"
  ];

  ezaIgnoreFlags = builtins.concatStringsSep " " (builtins.map (x: "--ignore-glob=\"${x}\"") customIgnores);
in {
  flake.nixosModules.ls = { pkgs, ...}: {
    imports = [
      # self.nixosModules.fd
      # self.nixosModules.fsel
    ];
    environment.systemPackages = with pkgs; [

  # 1. lsp: List ONLY persistent files/dirs (including hidden ones, minus customIgnores)
  (writeShellScriptBin "lsp" ''
    if [ -n "$1" ]; then target=$(realpath "$1"); else target="$PWD"; fi

    if [ -d "/persistent$target" ]; then
      eza -alhg --icons --octal-permissions ${ezaIgnoreFlags} "/persistent$target"
    else
      echo "Note: No persistent footprint exists for this directory."
    fi
  '')

  # 2. treep: Tree view of ONLY persistent files/dirs (including hidden ones, minus customIgnores)
  (writeShellScriptBin "treep" ''
    if [ -n "$1" ]; then target=$(realpath "$1"); else target="$PWD"; fi

    if [ -d "/persistent$target" ]; then
      eza --tree -a --icons=always --color=always --group-directories-first ${ezaIgnoreFlags} "/persistent$target" | less -r
    else
      echo "Note: No persistent footprint exists for this directory."
    fi
  '')

  # 3. lst: List ONLY temporary files/dirs (including hidden ones, minus customIgnores)
  (writeShellScriptBin "lst" ''
    if [ -n "$1" ]; then target=$(realpath "$1"); else target="$PWD"; fi
    persist_dir="/persistent$target"

    # Pre-seed the array with your global Nix ignores
    ignore_args=( ${ezaIgnoreFlags} )

    if [ -d "$persist_dir" ]; then
      # Dynamically append every file found in the persistent directory
      while IFS= read -r -d ' ' entry; do
        ignore_args+=("--ignore-glob=$entry")
      done < <(find "$persist_dir" -maxdepth 1 -mindepth 1 -printf "%P\0" 2>/dev/null)
    fi

    eza -alhg --icons --octal-permissions "''${ignore_args[@]}" "$target"
  '')

  # 4. treet: Tree view of ONLY temporary files/dirs (including hidden ones, minus customIgnores)
  (writeShellScriptBin "treet" ''
    if [ -n "$1" ]; then target=$(realpath "$1"); else target="$PWD"; fi
    persist_dir="/persistent$target"

    # Pre-seed the array with your global Nix ignores
    ignore_args=( ${ezaIgnoreFlags} )

    if [ -d "$persist_dir" ]; then
      while IFS= read -r -d ' ' entry; do
        ignore_args+=("--ignore-glob=$entry")
      done < <(find "$persist_dir" -maxdepth 1 -mindepth 1 -printf "%P\0" 2>/dev/null)
    fi

    eza --tree -a --icons=always --color=always --group-directories-first "''${ignore_args[@]}" "$target" | less -r
  '')

    ];
  };
}
