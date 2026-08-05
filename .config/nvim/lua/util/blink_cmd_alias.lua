-- ユーザーコマンドは大文字始まり必須のため、小文字エイリアスを cmdline 補完候補として注入する blink ソース
local M = {}

-- label = コマンドラインに表示する小文字名 / insertText = 実行される実コマンド
M.aliases = {
  tb = "TerminalBrowser",
}

function M.new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  return vim.fn.getcmdtype() == ":"
end

function M:get_completions(context, callback)
  local before_cursor = context.line:sub(1, context.cursor[2])
  local items = {}
  if before_cursor:match("^%s*%S*$") then
    for alias, command in pairs(M.aliases) do
      -- 挿入も小文字のまま (実行時は cnoreabbrev が実コマンドへ展開する)
      table.insert(items, {
        label = alias,
        filterText = alias,
        insertText = alias,
        kind = vim.lsp.protocol.CompletionItemKind.Function,
        documentation = ("小文字エイリアス → :%s"):format(command),
      })
    end
  end
  callback({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = items,
  })
  return function() end
end

return M
