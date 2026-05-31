return {
  -- markdownlint-cli2 を stdin で実行すると cwd 直下の設定しか探さないため、
  -- home 直下の ~/.markdownlint-cli2.jsonc が効かず既定の 80 文字制限に戻ってしまう。
  -- そこで --config で設定ファイルを絶対パス指定して常に適用させる。
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          prepend_args = { "--config", vim.fn.expand("~/.markdownlint-cli2.jsonc") },
        },
      },
    },
  },
}
