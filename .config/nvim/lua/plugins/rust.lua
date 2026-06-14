-- rust extra (lazyvim.json で有効化) は rust-analyzer を PATH から探すが、
-- システムには未導入なので mason で入れる。mason の bin は nvim 内で PATH に追加される。
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "rust-analyzer" })
    end,
  },
}
