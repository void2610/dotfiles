-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.lazyvim_picker = "telescope"

-- CJK 文字 (日本語等) をスペルチェック対象外にし、波線が出ないようにする
-- programming は開発用語辞書 (spell/programming.utf-8.spl)
vim.opt.spelllang = { "en", "cjk", "programming" }
