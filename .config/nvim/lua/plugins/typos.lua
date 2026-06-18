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
        marksman = {
          handlers = {
            -- code 2 = リンク先ドキュメント不在 (broken reference) の診断のみ抑制する
            ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
              if result and result.diagnostics then
                result.diagnostics = vim.tbl_filter(function(d)
                  return not (d.source == "Marksman" and d.code == 2)
                end, result.diagnostics)
              end
              return vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
            end,
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
