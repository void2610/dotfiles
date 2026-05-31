return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      -- 画像のインライン表示は image.nvim に一本化する。
      -- snacks.image も有効だと同じ画像が二重に描画されてしまうため無効化する。
      opts.image = opts.image or {}
      opts.image.enabled = false
      -- telescope を主 picker としつつ Snacks.picker は ui_select 用に有効化する。
      -- これで `vim.ui.select` のプロンプトが綺麗になり checkhealth 警告も消える。
      opts.picker = opts.picker or {}
      opts.picker.enabled = true
      opts.picker.ui_select = true
      opts.picker.sources = opts.picker.sources or {}
      -- explorer (ファイラ) のサイドバー幅を狭くする
      opts.picker.sources.explorer = vim.tbl_deep_extend("force", opts.picker.sources.explorer or {}, {
        layout = { layout = { width = 25 } },
      })
      -- <c-/> のターミナルを下分割ではなく画面中央のフロート (オーバーレイ) で開閉する
      opts.terminal = opts.terminal or {}
      opts.terminal.win = vim.tbl_deep_extend("force", opts.terminal.win or {}, {
        position = "float",
        width = 0.8,
        height = 0.8,
        border = "rounded",
      })
      -- ダッシュボードに定番レイアウトを開くキー (w) を追加する
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      opts.dashboard.preset.keys = opts.dashboard.preset.keys or {}
      table.insert(opts.dashboard.preset.keys, 1, {
        icon = "\239\131\155 ", -- nf-fa-columns (レイアウトを表すアイコン)
        key = "w",
        desc = "Open Workspace",
        action = function()
          require("util.workspace").open()
        end,
      })
    end,
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
