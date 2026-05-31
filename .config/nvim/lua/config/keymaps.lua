-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("i", "jj", "<ESC>", { silent = true })

-- workspace (ファイラ + 編集 + Claude Code) を開く
vim.keymap.set("n", "<leader>qw", function()
  require("util.workspace").open()
end, { desc = "Open workspace" })
