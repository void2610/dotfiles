return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      -- `<leader>y` 配下に y operator の motion 一覧を直接展開して登録する。
      -- motions preset の desc を流用するので、description ベースの自動アイコンも引き継がれる。
      opts.spec = opts.spec or {}
      -- ghq ランチャー (<leader>gr) のアイコン。リポジトリアイコン (nf-oct-repo) を使う。
      -- nf-oct-repo (U+F401) をバイトエスケープで指定する。
      table.insert(opts.spec, { "<leader>gr", icon = { icon = "\239\144\129 ", color = "green" } })
      table.insert(opts.spec, { "<leader>y", group = "yank", mode = "n" })
      local motions = require("which-key.plugins.presets").motions
      for _, m in ipairs(motions) do
        if type(m) == "table" and type(m[1]) == "string" then
          local key = m[1]
          table.insert(opts.spec, {
            "<leader>y" .. key,
            function()
              vim.api.nvim_feedkeys("y" .. key, "n", false)
            end,
            desc = m.desc,
            mode = "n",
          })
        end
      end
    end,
  },
}
