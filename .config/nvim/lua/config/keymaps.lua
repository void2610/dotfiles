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

-- 行内の col (byte index, 1 始まり) を含む URL を返す
local function find_url(line, col)
  local s = 1
  while true do
    local from, to = line:find("https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+", s)
    if not from then
      return nil
    end
    if col >= from and col <= to then
      return line:sub(from, to)
    end
    s = to + 1
  end
end

-- gx: カーソル位置の URL を既定ブラウザで開く (URL 以外はファイルパスとして開く)
vim.keymap.set("n", "gx", function()
  local url = find_url(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2] + 1)
  if not url then
    local cfile = vim.fn.expand("<cfile>")
    if cfile == "" then
      return
    end
    url = cfile
  end
  vim.ui.open(url)
end, { desc = "Open link under cursor" })

-- 左クリック: URL の上なら gx と同じロジックで開き、それ以外は通常のクリック動作
vim.keymap.set("n", "<LeftMouse>", function()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= 0 then
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, vim.api.nvim_win_get_buf(pos.winid), pos.line - 1, pos.line, true)
    if ok and lines[1] then
      local url = find_url(lines[1], pos.column)
      if url then
        vim.ui.open(url)
        return ""
      end
    end
  end
  return "<LeftMouse>"
end, { expr = true, desc = "Click to open URL" })

