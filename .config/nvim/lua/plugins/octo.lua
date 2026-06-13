return {
  -- octo extra の <leader>gr (Octo repo list) は作成順固定で実用性が無いため無効化し、
  -- 本来の <leader>gr を snacks.lua の ghq ランチャーに譲る。
  {
    "pwntester/octo.nvim",
    keys = {
      { "<leader>gr", false },
    },
  },
}
