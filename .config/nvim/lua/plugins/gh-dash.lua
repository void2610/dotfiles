return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>gh",
        function()
          -- nix で宣言的に入れた gh-dash バイナリを snacks のフロートターミナルで開く。
          Snacks.terminal.toggle("gh-dash", {
            win = {
              position = "float",
              width = 0.95,
              height = 0.95,
              border = "rounded",
            },
          })
        end,
        desc = "gh-dash",
      },
    },
  },
}
