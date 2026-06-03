-- typos-lsp によるスペルチェック。
-- 既知の誤字パターンのみ指摘するため、camelCase / 数字混じり / 大文字小文字差異に強い。
-- mason 経由で自動インストールされる。
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        typos_lsp = {
          init_options = {
            -- 誤字を Hint で表示 (うるさくしたければ "Warning")
            diagnosticSeverity = "Hint",
            -- ASCII 以外を無視する設定 (日本語の波線抑制)
            config = vim.fn.stdpath("config") .. "/typos.toml",
          },
        },
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      table.insert(opts.ensure_installed, "typos-lsp")
    end,
  },
}
