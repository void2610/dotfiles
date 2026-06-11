return {
  {
    "folke/snacks.nvim",
    keys = {
      -- ghq + snacks.picker リポジトリランチャー (旧 shell 関数 `g` 相当)
      {
        "<leader>gr",
        function()
          require("util.ghq").pick()
        end,
        desc = "ghq repositories",
      },
    },
    opts = function(_, opts)
      -- 画像のインライン表示は image.nvim に一本化する。
      -- snacks.image も有効だと同じ画像が二重に描画されてしまうため無効化する。
      opts.image = opts.image or {}
      opts.image.enabled = false
      -- snacks.picker を主 picker として有効化し、`vim.ui.select` も snacks に寄せる。
      opts.picker = opts.picker or {}
      opts.picker.enabled = true
      opts.picker.ui_select = true
      opts.picker.sources = opts.picker.sources or {}
      -- Unity のエディタ専用ファイル (テキストエディタで直接編集しない) を
      -- 検索結果から除外する (glob パターン)。
      local unity_exclude = {
        "*.meta", -- メタファイル
        "*.prefab", -- プレハブ
        "*.unity", -- シーン
        "*.mat", -- マテリアル
        "*.asset", -- アセット (ScriptableObject 等)
        "*.anim", -- アニメーションクリップ
        "*.controller", -- アニメーターコントローラー
      }
      -- ファイル検索 (find_files) と grep の両方で Unity 専用ファイルを除外する。
      -- また .github 等のドットディレクトリも検索対象に含めるため隠しファイルを表示する。
      for _, source in ipairs({ "files", "grep" }) do
        opts.picker.sources[source] = vim.tbl_deep_extend("force", opts.picker.sources[source] or {}, {
          hidden = true, -- ドットファイル (隠しファイル) を表示する
          exclude = vim.deepcopy(unity_exclude),
        })
      end
      -- explorer (ファイラ) のサイドバー幅を狭くする
      -- また Unity プロジェクト向けに専用ファイルを除外しつつ隠しファイルは表示する
      opts.picker.sources.explorer = vim.tbl_deep_extend("force", opts.picker.sources.explorer or {}, {
        layout = { layout = { width = 25 } },
        hidden = true, -- ドットファイル (隠しファイル) を表示する
        exclude = vim.deepcopy(unity_exclude),
      })
      -- lazygit のフロートサイズを指定
      opts.lazygit = opts.lazygit or {}
      opts.lazygit.win = vim.tbl_deep_extend("force", opts.lazygit.win or {}, {
        width = 0.93,
        height = 0.93,
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
