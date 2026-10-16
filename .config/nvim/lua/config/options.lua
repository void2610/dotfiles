-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- スペルチェックは typos-lsp (LSP) に一本化する。内蔵 spell は無効化する。
vim.opt.spell = false

-- タブタイトル用: gitsigns が検出したブランチ名を返す (git 外は空)
function _G.TitleBranch()
  local head = vim.b.gitsigns_head or vim.g.gitsigns_head
  return head and ("(" .. head .. ")") or ""
end

-- 内蔵ターミナルの Claude Code が hook (~/.claude/hooks/nvim-title-state.sh) から --remote-expr で呼ぶ
local claude_icons = { working = "⏳ ", waiting = "🔔 ", idle = "💤 ", done = "✅ " }
function _G.ClaudeTitleState(state)
  vim.g.claude_title_state = state
  vim.schedule(function()
    -- titlestring は再設定しないと再評価されない
    vim.o.titlestring = vim.o.titlestring
  end)
  return ""
end

function _G.TitleClaude()
  return claude_icons[vim.g.claude_title_state] or ""
end

-- ghostty 等のタブに「[Claude状態] dir(branch)・file ●」を表示する
vim.opt.title = true
vim.opt.titlestring =
  "%{v:lua.TitleClaude()}%{fnamemodify(getcwd(), ':t')}%{v:lua.TitleBranch()}・%t%{&modified ? ' ●' : ''}"
