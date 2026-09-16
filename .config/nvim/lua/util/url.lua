local M = {}

-- 行内の col (byte index, 1 始まり) を含む URL を返す
function M.find(line, col)
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

-- getmousepos() の戻り値が指す位置の URL を返す
function M.at_mouse(pos)
  if pos.winid == 0 or pos.line <= 0 then
    return nil
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, vim.api.nvim_win_get_buf(pos.winid), pos.line - 1, pos.line, true)
  if not ok or not lines[1] then
    return nil
  end
  return M.find(lines[1], pos.column)
end

return M
