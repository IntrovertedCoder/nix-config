{ self, inputs, config, ... }:
let
  c = config.var.colors;
in {
  flake.nixosModules.nvim = { pkgs, ...}: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];
    environment.systemPackages = with pkgs; [
    ];
    home-manager.users.shot = {
      home.packages = with pkgs; [
      ];

      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;

        plugins = with pkgs.vimPlugins; [
          # Vim plugins
          undotree

          # NVim plugins
          nvim-colorizer-lua
          mini-nvim
          git-blame-nvim
          rainbow-delimiters-nvim
          (nvim-treesitter.withAllGrammars)

          (pkgs.vimUtils.buildVimPlugin {
            name = "toggleword-nvim";
            src = pkgs.fetchFromGitHub {
              owner = "iquzart";
              repo = "toggleword.nvim";
              rev = "b2d0e49e3b33b9d8c15ac008aefc2bc5bbee5925"; # Pin specific commit
              hash = "sha256-ig9o5bNihfr7Ki3IWby4he2Oa7YsLIU3uQlDEEuBTHY=";
            };
          })
        ];
        initLua = /* lua */ ''
          -- Leader key
          vim.g.mapleader = " "

          --Temp
          vim.cmd('syntax on')
          vim.cmd('colorscheme vim')

          ---------------------------------------------------------------------
          -- Tabs, UI, Hidden Chars, and undo file
          ---------------------------------------------------------------------
          local opt = vim.opt

          -- Tabs
          opt.tabstop = 2
          opt.shiftwidth = 2
          opt.softtabstop = 2
          opt.expandtab = true
          opt.autoindent = true
          opt.smartindent = true

          -- UI
          opt.number = true
          opt.relativenumber = true
          opt.scrolloff = 5
          opt.termguicolors = true
          opt.colorcolumn = "80"
          vim.api.nvim_set_hl(0, 'ColorColumn', {bg = '#${c.grey1}', ctermbg = 235 })

          -- Invisible characters
          opt.list = true
          opt.listchars = { tab = "| ", trail = "+", eol = "$" }

          -- Persistent undo
          opt.undofile = true

          ---------------------------------------------------------------------
          -- Keymaps
          ---------------------------------------------------------------------
          local keymap = vim.keymap.set

          -- Undotree
          vim.g.undotree_WindowLayout = 3
          keymap('n', '<leader>u', '<cmd>UndotreeToggle<CR><cmd>wincmd h<CR><cmd>vertical resize 86<CR>', {silent = true})

          -- Repeat last macro
          keymap('n', ',', '@@')

          -- Find/replace
          keymap('n', '<leader>r', [[:%s/\<<C-r><C-w>\>//gI<Left><Left><Left>]])

          -- Insert blank lines
          keymap('n', '<leader>o', 'o<Esc>', { silent = true})
          keymap('n', '<leader>O', 'O<Esc>', { silent = true})

          ---------------------------------------------------------------------
          -- Autocommands
          ---------------------------------------------------------------------

          -- Remove end whitespace
          vim.api.nvim_create_autocmd("BufWritePre", {
            pattern = "*",
            callback = function()
              local save_cursor = vim.fn.getpos(".")
              vim.cmd([[%s/\s+$//e]])
              vim.fn.setpos(".", save_cursor)
            end,
          })

          ---------------------------------------------------------------------
          -- Plugins
          ---------------------------------------------------------------------

          -- Colorizer
          require('colorizer').setup({
            '*';
          }, {
            RGB = true;
            RRGGBB = true;
            names = true;
            RRGGBBAA = true;
            AARRGGBB = true;
            rgb_fn = true;
            hsl_fn = true;
            css = true;
            css_fn = true;

            mode = 'background'
          })

          -- Git Blame
          require('gitblame').setup({
            enabled = true,
          })

          -- Mini Indentscope
          require('mini.indentscope').setup({
          })

          -- Toggleword
          require('toggleword').setup({
            key = "<leader>t"
          })

          -- Rainbow Delimiters
          require('rainbow-delimiters.setup').setup({
            strategy = {
              [""] = require('rainbow-delimiters').strategy['global']
            },
            query = {
              [""] = 'rainbow-delimiters',
            },

            highlight = {
              'RainbowDelimiterRed',
              'RainbowDelimiterYellow',
              'RainbowDelimiterBlue',
              'RainbowDelimiterOrange',
              'RainbowDelimiterGreen',
              'RainbowDelimiterViolet',
              'RainbowDelimiterCyan',
            },
          })
          vim.api.nvim_set_hl(0, 'RainbowDelimiterRed', { fg = '#${c.red}' })
          vim.api.nvim_set_hl(0, 'RainbowDelimiterOrange', { fg = '#${c.orange}' })
          vim.api.nvim_set_hl(0, 'RainbowDelimiterYellow', { fg = '#${c.yellow}' })
          vim.api.nvim_set_hl(0, 'RainbowDelimiterGreen', { fg = '#${c.green}' })
          vim.api.nvim_set_hl(0, 'RainbowDelimiterBlue', { fg = '#${c.blue}' })
          vim.api.nvim_set_hl(0, 'RainbowDelimiterViolet', { fg = '#${c.magenta}' })
          vim.api.nvim_set_hl(0, 'RainbowDelimiterCyan', { fg = '#${c.cyan}' })

          -- Treesitter for rainbow delimiters in nix
          vim.api.nvim_create_autocmd('FileType', {
            callback = function()
              pcall(vim.treesitter.start)
            end,
          })

          ---------------------------------------------------------------------
          -- Theme
          ---------------------------------------------------------------------
          require('mini.base16').setup({
            palette = {
              base00 = "#${c.black}",
              base01 = "#${c.black2}",
              base02 = "#${c.grey2}",
              base03 = "#${c.grey3}",
              base04 = "#${c.white2}",
              base05 = "#${c.white}",
              base06 = "#${c.white1}",
              base07 = "#${c.black1}",
              base08 = "#${c.red}",
              base09 = "#${c.orange}",
              base0A = "#${c.yellow}",
              base0B = "#${c.green}",
              base0C = "#${c.blue}",
              base0D = "#${c.magenta}",
              base0E = "#${c.cyan}",
              base0F = "#${c.lgreen}",
            },
            use_cterm = true,
          })
          vim.api.nvim_set_hl(0, "@string.injected.bg", { 
            bg = "#${c.black1}", -- Replace this hex code with whatever background tint you prefer!
          })
        '';
      };
      xdg.configFile."nvim/queries/nix/highlights.scm".text = /* query */ ''
        ; extends

        ((comment) . [
          (string_expression)
          (indented_string_expression)
        ] @string.injected.bg)
      '';
    };
  };
}
