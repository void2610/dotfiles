return {
  {
    dir = vim.fn.expand("~/Documents/GitHub/zetema"),
    name = "zetema",
    cmd = { "Zetema", "ZetemaSource", "ZetemaAsk", "ZetemaMore", "ZetemaChat", "ZetemaReview", "ZetemaHistory", "ZetemaMode", "ZetemaViewed", "ZetemaView", "ZetemaJump" },
    keys = {
      { "<leader>zo", "<cmd>Zetema<cr>", desc = "zetema: diff を開く" },
      { "<leader>zs", "<cmd>ZetemaSource<cr>", desc = "zetema: repo/rev 切替" },
      { "<leader>za", ":ZetemaAsk<cr>", mode = "x", desc = "zetema: 選択範囲を問う" },
      { "<leader>zm", "<cmd>ZetemaMore<cr>", desc = "zetema: もっと詳しく" },
      { "<leader>zc", "<cmd>ZetemaChat<cr>", desc = "zetema: チャット" },
      { "<leader>zc", ":ZetemaChat<cr>", mode = "x", desc = "zetema: 選択を添えてチャット" },
      { "<leader>zr", "<cmd>ZetemaReview<cr>", desc = "zetema: 差分全体レビュー" },
      { "<leader>zh", "<cmd>ZetemaHistory<cr>", desc = "zetema: 履歴から開く" },
      { "<leader>zM", "<cmd>ZetemaMode<cr>", desc = "zetema: 診断モード切替" },
      { "<leader>zv", "<cmd>ZetemaViewed<cr>", desc = "zetema: 既読トグル" },
      { "<leader>zw", "<cmd>ZetemaView<cr>", desc = "zetema: 回答チャネル切替" },
    },
    -- キーマップは上の keys で lazy 管理するため、プラグイン内蔵マッピングは無効化する。
    opts = { keymap_prefix = "" },
  },
}
