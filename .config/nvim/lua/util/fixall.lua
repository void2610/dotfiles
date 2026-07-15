local M = {}

local CPP_FILETYPES = { c = true, cpp = true, objc = true, objcpp = true }

--- clangd は source.fixAll 未対応 (https://github.com/clangd/clangd/issues/1446) のため quickfix 一括適用で代替する (edit は位置ズレ防止のため一括で apply_text_edits に渡す)
--- @param bufnr integer
--- @return integer 適用した edit 件数
local function apply_quickfix_batch(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })
  if #clients == 0 then
    return 0
  end
  -- clangd 独自診断 (IncludeCleaner の unused-includes 等) や生の compiler エラーは安全な自動修正でないため対象外にする
  local lsp_diagnostics = vim.tbl_map(function(d)
    return d.user_data and d.user_data.lsp or d
  end, vim.diagnostic.get(bufnr))
  lsp_diagnostics = vim.tbl_filter(function(d)
    return d.source == "clang-tidy"
  end, lsp_diagnostics)
  if #lsp_diagnostics == 0 then
    return 0
  end

  local last_line = vim.api.nvim_buf_line_count(bufnr) - 1
  local last_col = #(vim.api.nvim_buf_get_lines(bufnr, last_line, last_line + 1, false)[1] or "")
  local uri = vim.uri_from_bufnr(bufnr)
  local applied = 0

  for _, client in ipairs(clients) do
    ---@type lsp.CodeActionParams
    local params = {
      textDocument = { uri = uri },
      range = { start = { line = 0, character = 0 }, ["end"] = { line = last_line, character = last_col } },
      context = { only = { "quickfix" }, diagnostics = lsp_diagnostics },
    }
    local resp = client:request_sync("textDocument/codeAction", params, 5000, bufnr)
    local edits = {}
    for _, action in ipairs((resp and resp.result) or {}) do
      local edit = action.edit
      if edit and edit.documentChanges then
        for _, change in ipairs(edit.documentChanges) do
          if change.textDocument and change.textDocument.uri == uri then
            vim.list_extend(edits, change.edits)
          end
        end
      elseif edit and edit.changes and edit.changes[uri] then
        vim.list_extend(edits, edit.changes[uri])
      end
    end
    if #edits > 0 then
      vim.lsp.util.apply_text_edits(edits, bufnr, client.offset_encoding)
      applied = applied + #edits
    end
  end
  return applied
end

--- 現在バッファの警告を一括修正する (explorer ツリーにフォーカス中は選択フォルダの一括修正 M.dir に委譲)
--- @param bufnr? integer
function M.buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local explorer = Snacks.picker.get({ source = "explorer" })[1]
  if explorer and explorer.list.win.buf == bufnr then
    M.dir(explorer:dir())
    return
  end
  local ft = vim.bo[bufnr].filetype
  if CPP_FILETYPES[ft] then
    local applied = apply_quickfix_batch(bufnr)
    if applied == 0 then
      vim.notify("適用可能な修正はありませんでした", vim.log.levels.INFO, { title = "Fix All" })
    else
      vim.notify(("%d 件の修正を適用しました"):format(applied), vim.log.levels.INFO, { title = "Fix All" })
    end
    return
  end
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })
  if #clients == 0 then
    vim.notify("Code Action 対応の LSP クライアントがありません", vim.log.levels.WARN, { title = "Fix All" })
    return
  end
  LazyVim.lsp.action["source.fixAll"]()
end

--- DiagnosticChanged / LspProgress (indexing 等) が settle_ms 途切れるまで待つ
--- @param bufnr integer
--- @param timeout_ms integer
--- @param settle_ms integer
local function wait_settled(bufnr, timeout_ms, settle_ms)
  local last_activity = vim.uv.now()
  local diag_id = vim.api.nvim_create_autocmd("DiagnosticChanged", {
    buffer = bufnr,
    callback = function()
      last_activity = vim.uv.now()
    end,
  })
  local prog_id = vim.api.nvim_create_autocmd("LspProgress", {
    callback = function()
      last_activity = vim.uv.now()
    end,
  })
  vim.wait(timeout_ms, function()
    return (vim.uv.now() - last_activity) >= settle_ms
  end, 100)
  pcall(vim.api.nvim_del_autocmd, diag_id)
  pcall(vim.api.nvim_del_autocmd, prog_id)
end

--- clangd がまれに空診断を publish したまま再計算しないことがあるため、末尾に無害な編集を入れて 1 度だけ再計算を促す
--- @param bufnr integer
local function nudge(bufnr)
  local last_line = vim.api.nvim_buf_line_count(bufnr) - 1
  local last_col = #(vim.api.nvim_buf_get_lines(bufnr, last_line, last_line + 1, false)[1] or "")
  vim.api.nvim_buf_set_text(bufnr, last_line, last_col, last_line, last_col, { " " })
  vim.api.nvim_buf_set_text(bufnr, last_line, last_col, last_line, last_col + 1, { "" })
end

--- @param bufnr integer
local function wait_diagnostics_ready(bufnr)
  wait_settled(bufnr, 20000, 1500)
  if #vim.diagnostic.get(bufnr) > 0 then
    return
  end
  nudge(bufnr)
  wait_settled(bufnr, 12000, 1500)
end

--- 1 ファイルを開いて警告を一括修正し、変更があれば保存する
--- @param path string
--- @return {path: string, status: string, applied?: integer}
function M.file(path)
  local ft = vim.filetype.match({ filename = path })
  if not ft or ft == "" then
    return { path = path, status = "no_filetype" }
  end

  local existing = vim.fn.bufnr(path) ~= -1
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  if vim.bo[bufnr].modified then
    return { path = path, status = "skipped_modified" }
  end
  vim.bo[bufnr].filetype = ft

  local attached = vim.wait(15000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" }) > 0
  end, 100)
  if not attached then
    if not existing then
      vim.api.nvim_buf_delete(bufnr, { unload = true, force = true })
    end
    return { path = path, status = "no_lsp" }
  end

  wait_diagnostics_ready(bufnr)
  local applied = apply_quickfix_batch(bufnr)
  if applied > 0 then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent write")
    end)
  end
  if not existing then
    vim.api.nvim_buf_delete(bufnr, { unload = true, force = true })
  end
  return { path = path, status = "ok", applied = applied }
end

--- git 管理下ならトラッキング/未追跡かつ .gitignore 対象外のファイルのみを対象にする (再帰、build 物・vendor submodule を除外)
--- @param dir string
--- @return string[]
local function list_files(dir)
  local res = vim.system({ "git", "-C", dir, "ls-files", "--cached", "--others", "--exclude-standard" }, { text = true })
    :wait()
  if res.code == 0 then
    local files = {}
    for _, name in ipairs(vim.split(res.stdout, "\n", { trimempty = true })) do
      table.insert(files, vim.fs.joinpath(dir, name))
    end
    return files
  end
  return vim.tbl_filter(function(f)
    return vim.fn.isdirectory(f) == 0
  end, vim.fn.globpath(dir, "**/*", false, true))
end

--- dir 配下の全ファイルを一括修正する (確認ダイアログあり)
--- @param dir string
function M.dir(dir)
  local files = list_files(dir)
  if #files == 0 then
    vim.notify("対象ファイルがありません", vim.log.levels.INFO, { title = "Fix All" })
    return
  end

  Snacks.picker.util.confirm(("%d 件のファイルを一括修正して保存しますか?"):format(#files), function()
    local stats = { ok = 0, applied = 0, no_filetype = 0, no_lsp = 0, skipped_modified = 0 }
    for _, path in ipairs(files) do
      local result = M.file(path)
      if result.status == "ok" then
        stats.ok = stats.ok + 1
        stats.applied = stats.applied + (result.applied or 0)
      else
        stats[result.status] = (stats[result.status] or 0) + 1
      end
    end
    vim.notify(
      ("%d ファイル処理・%d 件修正 (LSP対象外 %d, 未対応 %d, 未保存編集ありでスキップ %d)"):format(
        stats.ok,
        stats.applied,
        stats.no_filetype,
        stats.no_lsp,
        stats.skipped_modified
      ),
      vim.log.levels.INFO,
      { title = "Fix All" }
    )
  end)
end

return M
