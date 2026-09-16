-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("i", "jj", "<ESC>", { silent = true })

-- <C-d> (半ページ下) の逆として <C-e> で半ページ上にスクロール
vim.keymap.set({ "n", "v" }, "<C-e>", "<C-u>", { desc = "Scroll half page up" })

-- workspace (ファイラ + 編集 + Claude Code) を開く
vim.keymap.set("n", "<leader>qw", function()
  require("util.workspace").open()
end, { desc = "Open workspace" })

-- カレントバッファのパスをシステムクリップボードにヤンク
vim.keymap.set("n", "<leader>yp", function()
  -- カレント cwd はプラグインが変更しうるため、nvim 起動時の cwd (vim.g.launch_cwd) を基準に相対化する
  local abs_path = vim.fn.expand("%:p")
  local path = vim.fs.relpath(vim.g.launch_cwd, abs_path) or abs_path
  vim.fn.setreg("+", path)
  vim.notify(path, vim.log.levels.INFO, { title = "Yanked relative path" })
end, { desc = "Yank relative path" })

vim.keymap.set("n", "<leader>yP", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify(path, vim.log.levels.INFO, { title = "Yanked absolute path" })
end, { desc = "Yank absolute path" })

-- gx: カーソル位置の URL を既定ブラウザで開く (URL 以外はファイルパスとして開く)
vim.keymap.set("n", "gx", function()
  local url = require("util.url").find(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2] + 1)
  if not url then
    local cfile = vim.fn.expand("<cfile>")
    if cfile == "" then
      return
    end
    url = cfile
  end
  vim.ui.open(url)
end, { desc = "Open link under cursor" })

vim.keymap.set("n", "<leader>xF", function()
  require("util.fixall").buffer()
end, { desc = "Fix All" })

-- 左クリック: URL の上なら gx と同じロジックで開き、それ以外は通常のクリック動作
vim.keymap.set("n", "<LeftMouse>", function()
  local url = require("util.url").at_mouse(vim.fn.getmousepos())
  if url then
    vim.ui.open(url)
    return ""
  end
  return "<LeftMouse>"
end, { expr = true, desc = "Click to open URL" })


-- タブ操作 (LazyVim デフォルトの <leader><Tab> グループを上書き)
vim.keymap.set("n", "<leader><Tab>n", "<cmd>tabnew<cr>", { desc = "New Tab" })
vim.keymap.set("n", "<leader><Tab><Tab>", "<cmd>tabnext<cr>", { desc = "Next Tab" })
