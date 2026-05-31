-- ghq + telescope リポジトリランチャー
--
-- もともと shell 関数 `g` (ghq + fzf) で行っていたリポジトリ選択を、
-- nvim 内のフロート (telescope ピッカー) として開けるよう書き直したもの。
-- 各リポジトリの状態 (dirty / ahead / behind / branch) を一覧に表示し、
-- プレビューに git status とファイル一覧を出す。
-- 状態取得は元と同様 xargs -P で並列化し、telescope の非同期 finder に
-- ストリーミングで流し込むため、リポジトリ数が多くても素早く一覧が立ち上がる。
--
-- <CR> で選択すると、そのリポジトリへ cd し、続けて find_files を開く
-- (shell での `cd` 後にそのまま作業を始める挙動に相当)。

local M = {}

-- リポジトリ一覧と状態を 1 行 1 リポジトリ (タブ区切り) で出力する zsh スクリプト。
-- 出力フォーマット: dirty数 \t ahead \t behind \t name \t branch \t path
-- ahead / behind は upstream が無い場合 -1 を返す。
-- 色付けは telescope 側 (make_display) で行うため、ここではプレーンな値のみ出す。
-- `]]` を含む zsh の `[[ ]]` と Lua の長括弧が衝突しないよう [==[ ]==] で囲う。
local LIST_SCRIPT = [==[
local -a extra
for p in "$HOME/dotfiles" "$HOME/nix-config"; do
  [[ -d $p/.git ]] && extra+=("$p")
done
{ ghq list -p; print -l $extra } \
  | grep -vE '/(\.venv|venv|node_modules|vendor|\.tox|\.pixi|\.cargo|target|Pods|Packages|site-packages)/' \
  | xargs -P 16 -I {} zsh -c '
      repo=$1
      br=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo "(detached)")
      ws=$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null)
      if [[ -n $ws ]]; then n=$(print -r -- "$ws" | wc -l | tr -d " "); else n=0; fi
      if git -C "$repo" rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1; then
        a=$(git -C "$repo" rev-list --count "@{u}..HEAD" 2>/dev/null)
        b=$(git -C "$repo" rev-list --count "HEAD..@{u}" 2>/dev/null)
      else
        a=-1; b=-1
      fi
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$n" "$a" "$b" "${repo:t}" "$br" "$repo"
    ' _ {}
]==]

-- リポジトリのフルパスからホーム以下を ~ に短縮して返す。
local function short_path(path)
  return vim.fn.fnamemodify(path, ":~")
end

function M.pick(opts)
  opts = opts or {}

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  -- 各カラムの表示幅。dirty / ahead / behind / name / branch / path の順。
  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 4 },
      { width = 4 },
      { width = 4 },
      { width = 30 },
      { width = 24 },
      { remaining = true },
    },
  })

  -- 1 エントリを色付きで整形する。色はテーマ追従の標準 hl グループを使う。
  local function make_display(entry)
    local dirty = entry.dirty > 0 and { "*" .. entry.dirty, "DiagnosticError" }
      or { ".", "Comment" }

    local ahead, behind
    if entry.ahead < 0 then
      -- upstream 無し
      ahead = { "↑-", "Comment" }
      behind = { "↓-", "Comment" }
    else
      ahead = entry.ahead > 0 and { "↑" .. entry.ahead, "DiagnosticOk" } or { "↑0", "Comment" }
      behind = entry.behind > 0 and { "↓" .. entry.behind, "DiagnosticWarn" } or { "↓0", "Comment" }
    end

    return displayer({
      dirty,
      ahead,
      behind,
      { entry.name, "TelescopeResultsIdentifier" },
      { entry.branch, "Comment" },
      { short_path(entry.value), "Comment" },
    })
  end

  -- finder の 1 行 (タブ区切り) を telescope エントリに変換する。
  local function entry_maker(line)
    local n, a, b, name, branch, path = line:match("^(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.+)$")
    if not path then
      return nil
    end
    return {
      value = path,
      path = path,
      name = name,
      branch = branch,
      dirty = tonumber(n) or 0,
      ahead = tonumber(a) or -1,
      behind = tonumber(b) or -1,
      -- 絞り込み対象 (リポジトリ名 + ブランチ + パス)
      ordinal = name .. " " .. branch .. " " .. path,
      display = make_display,
    }
  end

  -- プレビュー: git status と eza/ls によるファイル一覧 (元スクリプトと同じ)。
  local previewer = previewers.new_termopen_previewer({
    get_command = function(entry)
      local p = vim.fn.shellescape(entry.path)
      return {
        "zsh",
        "-lc",
        string.format(
          "git -C %s -c color.status=always status -sb 2>/dev/null; echo; "
            .. "eza -la --icons --color=always %s 2>/dev/null || ls -la %s",
          p,
          p,
          p
        ),
      }
    end,
  })

  pickers
    .new(opts, {
      prompt_title = "ghq repositories",
      finder = finders.new_async_job({
        command_generator = function()
          return { "zsh", "-lc", LIST_SCRIPT }
        end,
        entry_maker = entry_maker,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewer,
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not entry then
            return
          end
          -- 選択リポジトリへ移動し、そのまま作業を始められるよう find_files を開く。
          vim.cmd.cd(vim.fn.fnameescape(entry.path))
          require("telescope.builtin").find_files({ cwd = entry.path })
        end)
        return true
      end,
    })
    :find()
end

return M
