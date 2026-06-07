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
      -- また Unity プロジェクト向けに .meta ファイルを除外しつつ隠しファイルは表示する
      opts.picker.sources.explorer = vim.tbl_deep_extend("force", opts.picker.sources.explorer or {}, {
        layout = { layout = { width = 25 } },
        hidden = true, -- ドットファイル (隠しファイル) を表示する
        -- Unity のエディタ専用ファイル (テキストエディタで直接編集しない) を非表示にする
        exclude = {
          "*.meta", -- メタファイル
          "*.prefab", -- プレハブ
          "*.unity", -- シーン
          "*.mat", -- マテリアル
          "*.asset", -- アセット (ScriptableObject 等)
          "*.anim", -- アニメーションクリップ
          "*.controller", -- アニメーターコントローラー
        },
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
      -- <C-/> の初回起動時に zsh 初期化の待ち時間が発生するため、
      -- nvim 起動完了後にバックグラウンドで zsh ターミナルを生成しておく。
      -- LazyVim の `<C-/>` (Snacks.terminal.focus(nil, { cwd = LazyVim.root() }))
      -- と同じ cmd/cwd で open することで、snacks 側で同一 terminal id として
      -- 再利用され、押下時には既に初期化済みのバッファが表示される。
      -- 同期的に open → hide することで描画前に window を閉じ、フリッカーも回避する。
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          vim.schedule(function()
            local cwd
            if LazyVim and LazyVim.root then
              local ok_root, root = pcall(LazyVim.root)
              if ok_root then
                cwd = root
              end
            end
            cwd = cwd or vim.fn.getcwd(0)
            local ok_open, term = pcall(function()
              return require("snacks").terminal.open(nil, {
                cwd = cwd,
                win = { enter = false },
              })
            end)
            if ok_open and term and term.hide then
              term:hide()
            end
          end)
        end,
      })
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
