return {
  { import = "lazyvim.plugins.extras.editor.telescope" },
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        -- Unity の .meta ファイルを検索結果から除外する (Lua パターン)
        file_ignore_patterns = { "%.meta$" },
      },
    },
    keys = {
      -- ghq + telescope リポジトリランチャー (旧 shell 関数 `g` 相当)
      {
        "<leader>gr",
        function()
          require("util.ghq").pick()
        end,
        desc = "ghq repositories",
      },
    },
  },
  {
    -- which-key のアイコンは plugin spec の keys では指定できない (vim.keymap.set が弾く) ため、
    -- which-key 側の spec で設定する。telescope アイコンは多用されているため
    -- リポジトリアイコン (nf-oct-repo) を使う。
    "folke/which-key.nvim",
    opts = {
      spec = {
        -- nf-oct-repo (U+F401) をバイトエスケープで指定する
        { "<leader>gr", icon = { icon = "\239\144\129 ", color = "green" } },
      },
    },
  },
}
