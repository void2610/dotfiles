return {
  {
    "folke/snacks.nvim",
    opts = {
      image = { enabled = true },
      -- telescope を主 picker としつつ Snacks.picker は ui_select 用に有効化する。
      -- これで `vim.ui.select` のプロンプトが綺麗になり checkhealth 警告も消える。
      picker = { enabled = true, ui_select = true },
    },
    config = function(_, opts)
      require("snacks").setup(opts)
      -- nvim-treesitter v2 の registry に norg がなく Neorg plugin 経由でしか入らないため、
      -- Snacks.image.langs() の結果から norg を除外して checkhealth の警告を消す。
      local image = require("snacks.image")
      local orig = image.langs
      image.langs = function()
        return vim.tbl_filter(function(l)
          return l ~= "norg"
        end, orig())
      end
      -- LazyVim は vim.o.statuscolumn を LazyVim.statuscolumn() で直接設定しており、
      -- snacks.statuscolumn は意図的に無効。これに対する checkhealth 警告を抑止する。
      require("snacks.statuscolumn").meta.health = false
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "css",
        "latex",
        "scss",
        "svelte",
        "typst",
        "vue",
      })
    end,
  },
}
