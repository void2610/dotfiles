local M = {}

-- いつもの作業レイアウトを現在のタブに展開する
-- 左: ファイラ (snacks explorer) / 中央: 編集ペイン / 右: Claude Code
-- ターミナルは <c-/> で都度トグルして使う
function M.open()
  vim.cmd("only") -- 現在のタブを単一ウィンドウに整理
  local edit_win = vim.api.nvim_get_current_win() -- 中央の編集ペインを記録
  -- 左端にファイラを表示 (snacks.nvim の explorer)
  Snacks.explorer.open({ layout = { layout = { width = 30 } } })
  require("lazy").load({ plugins = { "claudecode.nvim" } }) -- 遅延ロードを確定させる
  vim.cmd("ClaudeCode") -- 右側に Claude Code を表示
  -- フォーカスを中央の編集ペインに戻す
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(edit_win) then
      vim.api.nvim_set_current_win(edit_win)
    end
  end)
end

return M
