-- C# の XML ドキュメントコメント (///) のタグ装飾を conceal して読みやすくする。
--   <summary> 等のタグは隠し、<see cref="X"/> は参照名 X だけを残す。
--   カーソルがある行ではタグが展開され、実際の記述を確認・編集できる (concealcursor = "")。
--
-- なぜ extmark か (他方式が使えない理由):
--   ・treesitter のインジェクションは現環境では C# doc コメントを xml として解決できない。
--   ・treesitter ハイライト有効時は vim の syntax エンジンが描画されず syntax conceal が効かない。
--   ・matchadd の conceal は concealcursor を無視するためカーソル行で展開できない。
--   extmark の conceal は treesitter と独立に描画され、かつ concealcursor を尊重するので
--   「タグを隠す」と「カーソル行で展開」を両立できる。
--
-- generics の誤爆回避:
--   対象を「/// で始まる行」に限定するため、List<int> 等コード本体は隠さない。

vim.opt_local.conceallevel = 2
vim.opt_local.concealcursor = "" -- カーソル行ではタグを展開する

local ns = vim.api.nvim_create_namespace("cs_doc_conceal")

-- 1 行分のタグ装飾に conceal extmark を付与する
local function conceal_line(buf, lnum, line)
  if not line:find("^%s*///") then return end -- /// 行のみ対象
  -- 表示上の中身を計算する (see cref 等は属性値を残し、その他のタグは除去)。
  -- これが空なら <summary> 等「装飾だけの行」なので conceal_lines で行ごと消す
  -- (空行すら残さず、上下の行が詰まる)。
  local visible = line:gsub("<[^>]->", function(tag)
    if tag:sub(-2) == "/>" and tag:find('="') then
      return tag:match('="([^"]*)"') or "" -- self-closing タグの属性値は残す
    end
    return ""
  end)
  visible = visible:gsub("^%s*///", ""):gsub("%s", "")
  if visible == "" then
    vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { conceal_lines = "" })
    return
  end
  local idx = 1
  while true do
    local s, e = line:find("<[^>]->", idx) -- 行内の <...> を順に拾う
    if not s then break end
    idx = e + 1
    local tag = line:sub(s, e)
    local base = s - 1 -- タグ先頭の 0-indexed バイト位置
    if tag:sub(-2) == "/>" and tag:find('="') then
      -- <see cref="X"/> : 属性値 X を残し、前後の装飾だけ隠す
      local q = tag:find('="') + 1 -- 値を囲む最初の " の位置 (タグ内 1-indexed)
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, base, { end_col = base + q, conceal = "" })
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, base + #tag - 3, { end_col = base + #tag, conceal = "" })
    else
      -- <summary> </summary> <param name="X"> 等は丸ごと隠す
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, base, { end_col = e, conceal = "" })
    end
  end
end

-- バッファ全体を再走査して conceal を貼り直す
local function refresh(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, l in ipairs(lines) do
    conceal_line(buf, i - 1, l)
  end
end

-- 編集に追従して貼り直す (バッファごとに一度だけ登録)
if not vim.b.cs_doc_conceal_setup then
  vim.b.cs_doc_conceal_setup = true
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = vim.api.nvim_create_augroup("CsDocConceal", { clear = false }),
    buffer = 0,
    callback = function(a) refresh(a.buf) end,
  })
end
refresh(0)
