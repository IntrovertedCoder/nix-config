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

          -- Folds
          vim.opt.foldmethod = "marker"

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

          -- Run vs
          vim.keymap.set("n", "<leader>vs", "<cmd>tabnew | term vs<cr>i", { desc = "Run vs script in new tab" })

          -- Runs lg
          vim.keymap.set("n", "<leader>lg", "<cmd>vsplit | term lg<cr>i", { desc = "Open Yazi in vertical split" })

          -- Runs nh os switch
          vim.keymap.set("n", "<leader>rb", "<cmd>vsplit | term nh os switch<cr>i", { desc = "Open Yazi in vertical split" })

          -- Open Yazi in a split window
          vim.keymap.set("n", "<leader>yz", "<cmd>vsplit | term yazi<cr>i", { desc = "Open Yazi in vertical split" })

            -- Automatically enter insert mode when a terminal opens
            vim.api.nvim_create_autocmd("TermOpen", {
              pattern = "*",
              callback = function()
                vim.cmd("startinsert")
                -- Optional: Turn off line numbers in terminal windows for a cleaner look
                vim.opt_local.number = false
                vim.opt_local.relativenumber = false
              end,
            })

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
            bg = "#${c.black1}",
          })

          ---------------------------------------------------------------------
          -- Dynamic Nix Color Highlighting (Standalone Color Names)
          ---------------------------------------------------------------------
          local nix_colors = {
            ${pkgs.lib.concatStringsSep ",\n  " (
              pkgs.lib.mapAttrsToList 
                (name: hex: ''${name} = "#${hex}"'') 
                (pkgs.lib.filterAttrs (n: v: builtins.isString v) c)
            )}
          }

          local function get_contrast_fg(hex)
            local h = hex:gsub("#", "")
            local r = tonumber("0x" .. h:sub(1, 2))
            local g = tonumber("0x" .. h:sub(3, 4))
            local b = tonumber("0x" .. h:sub(5, 6))
            if not r or not g or not b then return "#ffffff" end
            local luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            return luminance > 0.5 and "#000000" or "#ffffff"
          end

          -- Highlight color names
          for name, hex in pairs(nix_colors) do
            if not name:match(".*[rgb]$") or nix_colors[name:sub(1, -2)] == nil then
              local group_name = "NixColor_" .. name

              -- Set background to the hex color, and foreground to the contrast color
              vim.api.nvim_set_hl(0, group_name, { bg = hex, fg = get_contrast_fg(hex) })

              vim.fn.matchadd(group_name, [[\<]] .. name .. [[\>]])
            end
          end

          -- Helper: Convert hex strings to RGB components
          local function hex_to_rgb(hex)
            local h = hex:gsub("#", "")
            local r = tonumber("0x" .. h:sub(1, 2))
            local g = tonumber("0x" .. h:sub(3, 4))
            local b = tonumber("0x" .. h:sub(5, 6))
            return r, g, b
          end

          -- Core Engine: Finds the mathematical closest match in your dynamic palette
          local function find_closest_color(target_hex)
            local tr, tg, tb = hex_to_rgb(target_hex)
            if not tr or not tg or not tb then
              print("Invalid hex color format: " .. tostring(target_hex))
              return
            end

            local closest_name = ""
            local min_dist = math.huge

            for name, hex in pairs(nix_colors) do
              if not name:match(".*[rgb]$") or nix_colors[name:sub(1, -2)] == nil then
                local r, g, b = hex_to_rgb(hex)
                if r and g and b then
                  local dist = math.sqrt((tr - r)^2 + (tg - g)^2 + (tb - b)^2)
                  if dist < min_dist then
                    min_dist = dist
                    closest_name = name
                  end
                end
              end
            end

            local accuracy = (1 - (min_dist / 441.67)) * 100

            -- Outputs a clean format ready for copy-pasting directly back into Nix configuration files
            print(string.format("Closest: ''${c.%s} (%s) | Match: %.1f%%", closest_name, nix_colors[closest_name], accuracy))
          end

          -- Expose the utility command (nargs = '?' makes the argument optional)
          vim.api.nvim_create_user_command('ClosestColor', function(opts)
            local target = opts.args

            -- If no argument is provided, auto-extract the hex code under the cursor
            if target == "" then
              local word = vim.fn.expand("<cWORD>")
              -- Clean the string and look for standard 6-digit or 3-digit hex strings
              target = word:match("#?%x%x%x%x%x%x") or word:match("#?%x%x%x")

              if not target then
                print("No valid hex color found under the cursor.")
                return
              end
            end

            find_closest_color(target)
          end, { nargs = '?' })

          -- Keymap: Press <leader>cc over any hex code to evaluate it instantly
          vim.keymap.set('n', '<leader>cc', ':ClosestColor<CR>', { 
            desc = 'Find closest Nix palette color under cursor', 
            silent = true 
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
