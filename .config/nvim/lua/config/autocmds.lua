-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- スペルチェックは typos-lsp 一本化のため、LazyVim が text/markdown/gitcommit 等で
-- buffer-local に spell を強制 ON にする autocmd を解除する。
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")

-- 外部 (Claude Code 等) でファイルが変更されたら自動で再読み込みする。
-- LazyVim 既定の checktime は FocusGained/TermClose/TermLeave のみのため、
-- フォーカスを失わずにウィンドウ・バッファを移動した場合もカバーする。
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("shuya_checktime", { clear = true }),
  callback = function()
    if vim.o.buftype == "" then
      vim.cmd("checktime")
    end
  end,
})

-- 素の shell ターミナルでだけ jj でノーマルモードに戻れるようにする。
-- lazygit などの TUI で jj が誤爆するのを避けるため、buffer 名から起動コマンドを判定して
-- shell の場合のみ buffer-local にマップする。
vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("shuya_term_jj", { clear = true }),
  callback = function(args)
    -- term:// バッファ名は `term://<cwd>//<pid>:<cmd>` の形式。先頭の実行ファイル部分だけ取り出す。
    local name = vim.api.nvim_buf_get_name(args.buf)
    local cmd = name:match("term://.-//%d+:(.*)$") or ""
    local first = cmd:match("^(%S+)") or ""
    local basename = first:match("([^/]+)$") or ""
    local allowed = {
      zsh = true,
      bash = true,
      sh = true,
      fish = true,
      dash = true,
      claude = true, -- claudecode.nvim の Claude Code セッション
    }
    if allowed[basename] then
      vim.keymap.set("t", "jj", [[<C-\><C-n>]], { buffer = args.buf, silent = true })
    end
  end,
})

-- PR レビュー用に gitsigns の比較先 (base) を自動で切り替える。
-- gh pr checkout 等でブランチが変わると、gitsigns の gitdir watcher が HEAD 変更を検知して
-- User GitSignsUpdate を発火するので、そこで現在ブランチを確認し、
-- デフォルトブランチ以外では「マージ先との merge-base」を base にする。
-- これでサイン列や :Gitsigns diffthis が GitHub の Files changed と同じ範囲 (PR 差分) になる。
-- デフォルトブランチに戻ると通常の index 比較に戻す。
-- 制約: base はグローバル設定のため、複数リポジトリを同時に開くと最後に更新された方が勝つ。
do
  local applied_base = nil -- 適用済みの base (不要な change_base 呼び出しを避ける)
  local last_key = nil -- 前回処理した「リポジトリ + ブランチ」(編集等による再発火を無視する)
  local default_branch = {} -- リポジトリルート → "origin/main" 等のキャッシュ

  -- デフォルトブランチ (origin/HEAD) を非同期に解決して callback に渡す
  local function resolve_default_branch(root, callback)
    if default_branch[root] then
      return callback(default_branch[root])
    end
    vim.system(
      { "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" },
      { cwd = root, text = true },
      function(res)
        local ref = res.code == 0 and vim.trim(res.stdout) or ""
        if ref ~= "" then
          default_branch[root] = ref
          return callback(ref)
        end
        -- origin/HEAD 未設定のリポジトリでは origin/main → origin/master の順で存在確認する
        vim.system({ "git", "rev-parse", "--verify", "--quiet", "origin/main" }, { cwd = root }, function(r2)
          local fallback = r2.code == 0 and "origin/main" or "origin/master"
          default_branch[root] = fallback
          callback(fallback)
        end)
      end
    )
  end

  local function apply_base(base)
    if base == applied_base then
      return
    end
    applied_base = base
    vim.schedule(function()
      require("gitsigns").change_base(base, true)
    end)
  end

  vim.api.nvim_create_autocmd("User", {
    pattern = "GitSignsUpdate",
    group = vim.api.nvim_create_augroup("shuya_gitsigns_pr_base", { clear = true }),
    callback = function(ev)
      local buf = ev.data and ev.data.buffer
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local status = vim.b[buf].gitsigns_status_dict or {}
      local head, root = status.head, status.root
      if not head or head == "" or not root then
        return
      end
      local key = root .. "\0" .. head
      if key == last_key then
        return
      end
      last_key = key
      resolve_default_branch(root, function(default_ref)
        if head == default_ref:gsub("^origin/", "") then
          -- デフォルトブランチ上では通常の index 比較に戻す
          apply_base(nil)
          return
        end
        -- マージ先との分岐点 (merge-base) を base にして PR 差分を表示する
        vim.system({ "git", "merge-base", default_ref, "HEAD" }, { cwd = root, text = true }, function(res)
          if res.code == 0 then
            apply_base(vim.trim(res.stdout))
          end
        end)
      end)
    end,
  })
end
