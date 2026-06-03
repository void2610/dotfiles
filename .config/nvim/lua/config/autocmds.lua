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
