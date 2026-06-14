return {
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>go",
        function()
          -- 現在バッファのリポジトリで起動し、gh-dash の smartFilteringAtLaunch で当該リポジトリに自動スコープさせる。
          local file = vim.api.nvim_buf_get_name(0)
          local cwd = file ~= "" and vim.fs.dirname(file) or nil
          -- nix で宣言的に入れた gh-dash バイナリを snacks のフロートターミナルで開く。
          Snacks.terminal.toggle("gh-dash", {
            cwd = cwd,
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
