{ self, inputs, ... }: {
  flake.nixosModules.rgf = { pkgs, ...}: {
    imports = [
      # self.nixosModules.fd
      # self.nixosModules.fsel
    ];
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "rgf" ''
        # Sane base flags for the live ripgrep stream (POSIX syntax)
        RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case"

        fzf --ansi --disabled \
            --query "$*" \
            --bind "change:reload:$RG_PREFIX {q} || true" \
            --delimiter : \
            --preview 'bat --color=always --style=numbers --highlight-line {2} {1}' \
            --preview-window 'right,60%,+{2}-/2' \
            --bind 'enter:become(nvim +{2} {1})'
      '')
    ];
  };
}
