-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("i", "jj", "<ESC>", { silent = true })

-- workspace (ファイラ + 編集 + Claude Code) を開く
vim.keymap.set("n", "<leader>qw", function()
  require("util.workspace").open()
end, { desc = "Open workspace" })

-- カレントバッファのパスをシステムクリップボードにヤンク
vim.keymap.set("n", "<leader>yp", function()
  local path = vim.fn.expand("%")
  vim.fn.setreg("+", path)
  vim.notify(path, vim.log.levels.INFO, { title = "Yanked relative path" })
end, { desc = "Yank relative path" })

vim.keymap.set("n", "<leader>yP", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify(path, vim.log.levels.INFO, { title = "Yanked absolute path" })
end, { desc = "Yank absolute path" })

-- Ctrl + 左クリックでカーソル位置の URL/パスを既定アプリで開く
vim.keymap.set({ "n", "x" }, "<C-LeftMouse>", "<LeftMouse>gx", { desc = "Open link under cursor" })

