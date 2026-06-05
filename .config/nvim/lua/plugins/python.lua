-- Python 開発環境を polaris (https://github.com/akariinc/polaris 相当) のツールチェーンに合わせる。
--
-- polaris の Taskfile.yml では以下を使用している:
--   - 型チェック: ty   (task typecheck)
--   - lint / format:   ruff (task lint / task format)
--
-- LazyVim の `lang.python` extra (lazyvim.json で有効化) は
-- pyright + ruff を有効にするため、ここで pyright を無効化して ty に差し替える。
-- ruff は extra の設定をそのまま使う (LSP として lint と保存時フォーマットを提供)。
--
-- 備考:
--   - ty は project root の `.venv` を自動検出し、`pyproject.toml` の [tool.ty] を読む。
--   - extra は ruff の hoverProvider を無効化しているので、hover は ty が担当する。
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- extra が `enabled = true` にする pyright を上書きで無効化する
        -- (この spec は extra より後に評価されるため上書きが効く)
        pyright = { enabled = false },
        -- ty を LSP として有効化 (mason 経由で自動インストールされる)
        ty = {
          -- プロジェクトが ty を pin している場合 (polaris は dev deps に ty==0.0.40)、
          -- バージョン差で `task typecheck` と診断がズレないよう root の .venv/bin/ty を
          -- 優先する。無ければ mason の ty にフォールバックする。
          cmd = function(dispatchers, config)
            local bin = "ty"
            local root = config and config.root_dir
            if root then
              local venv_ty = root .. "/.venv/bin/ty"
              if vim.fn.executable(venv_ty) == 1 then
                bin = venv_ty
              end
            end
            return vim.lsp.rpc.start({ bin, "server" }, dispatchers, { cwd = root })
          end,
        },
      },
    },
  },
}
