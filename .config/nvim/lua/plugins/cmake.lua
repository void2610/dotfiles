-- LazyVim の lang.cmake extra が有効化する cmakelint の挙動を調整する。
-- linelength (C0301) は CMake ではノイズになりやすいので無効化する。
return {
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters = opts.linters or {}
      local cmakelint = opts.linters.cmakelint or {}
      cmakelint.args = vim.list_extend({ "--filter=-linelength" }, cmakelint.args or { "-" })
      opts.linters.cmakelint = cmakelint
    end,
  },
}
