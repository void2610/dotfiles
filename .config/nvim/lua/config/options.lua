-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.lazyvim_picker = "telescope"

-- スペルチェックは typos-lsp (LSP) に一本化する。内蔵 spell は無効化する。
vim.opt.spell = false
