local M = {}

-- 直近に開いた lazygit の float を保持し、RPC 経由の hide 対象にする。
local win = nil

function M.open(opts)
  win = require("snacks").lazygit(opts)
  return win
end

-- nvim 内 lazygit の `q` から nvim RPC 経由で呼ばれる。終了せず float を隠すことで lazygit プロセスを生かし、裏の push/生成を完走させスピナーも継続させる。
function M.hide()
  pcall(function()
    if win and win:valid() then
      win:hide()
    end
  end)
  return 0
end

_G.LazygitHide = M.hide

return M
