local M = {}

-- lazygit の画像 diff (image-diff.sh) から nvim RPC 経由で呼ばれる。外側の端末への書き込みを TUI に一本化し、nvim 自身の再描画と kitty graphics の APC が混線するのを防ぐ。
function M.send_to_terminal(path)
  local f = io.open(path, "rb")
  if not f then
    return 1
  end
  local data = f:read("*a")
  f:close()
  vim.api.nvim_ui_send(data)
  return 0
end

_G.LazygitSendToTerminal = M.send_to_terminal

return M
