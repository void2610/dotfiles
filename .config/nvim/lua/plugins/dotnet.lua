-- C# (.cs) の保存時フォーマットを CSharpier から Roslyn(OmniSharp) の LSP format に切り替える。
--
-- 背景:
--   LazyVim の `lang.dotnet` extra は conform の formatters_by_ft に `cs = { "csharpier" }`
--   を設定しており、保存のたびに CSharpier がファイル全体を整形する。
--   しかし CSharpier は独自スタイル固定の opinionated フォーマッタで、プロジェクトの
--   `.editorconfig`(csharp_* / dotnet_* ルール) をほぼ尊重しない。
--   この結果、`.editorconfig` + `dotnet format`(独自アナライザ含む) を整形の正としている
--   リポジトリでは、保存ごとに規約と食い違う整形で上書きされてしまう。
--
-- 対応:
--   conform から cs のフォーマッタ指定を取り除く。LazyVim の conform デフォルトは
--   `default_format_opts.lsp_format = "fallback"` なので、cs にフォーマッタが無ければ
--   保存時整形は自動的に LSP format(OmniSharp/Roslyn) にフォールバックする。
--   OmniSharp は Roslyn ベースで `.editorconfig` の csharp_* / dotnet_* スタイルを読むため、
--   CSharpier より規約に近い整形になる。
--   独自アナライザ(VUA1001 等)の自動修正までは保存時には適用されないため、最終的な整形は
--   従来どおりプロジェクトの `run-format.sh`(dotnet format) で揃える運用とする。
return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      -- nil にして cs のエントリを消すことで、conform は cs にフォーマッタを持たず
      -- lsp_format = "fallback" 経由で LSP format が使われる。
      opts.formatters_by_ft.cs = nil
    end,
  },
}
