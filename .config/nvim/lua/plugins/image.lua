return {
  {
    "3rd/image.nvim",
    -- imagemagick がないマシン (Jetson 最小構成) では rockspec ビルドも実行時描画も不可能なため無効化する。
    enabled = vim.fn.executable("magick") == 1,
    build = "rockspec",
    event = "VeryLazy",
    opts = {},
  },
}
