return {
  {
    dir = vim.fn.expand("~/Documents/GitHub/zetema"),
    name = "zetema",
    cmd = { "Zetema", "ZetemaSource", "ZetemaAsk" },
    keys = {
      { "<leader>zo", "<cmd>Zetema<cr>", desc = "zetema: diff を開く" },
      { "<leader>zs", "<cmd>ZetemaSource<cr>", desc = "zetema: repo/rev 切替" },
      { "<leader>za", ":ZetemaAsk<cr>", mode = "x", desc = "zetema: 選択範囲を問う" },
    },
    -- キーマップは上の keys で lazy 管理するため、プラグイン内蔵マッピングは無効化する。
    opts = { keymap_prefix = "" },
  },
}
