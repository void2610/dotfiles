-- ghq + telescope リポジトリランチャー
--
-- もともと shell 関数 `g` (ghq + fzf) で行っていたリポジトリ選択を、
-- nvim 内のフロート (telescope ピッカー) として開けるよう書き直したもの。
-- 各リポジトリの状態 (dirty / ahead / behind / branch) を一覧に表示し、
-- プレビューに README (bat) とコミット履歴を出す。
-- 状態取得は元と同様 xargs -P で並列化し、telescope の非同期 finder に
-- ストリーミングで流し込むため、リポジトリ数が多くても素早く一覧が立ち上がる。
--
-- <CR> で選択すると、そのリポジトリへ cd する (shell での `cd` 相当)。

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

function M.pick(opts)
  opts = opts or {}

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  -- 各カラムの表示幅。dirty / ahead / behind / name / branch の順。
  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 4 },
      { width = 4 },
      { width = 4 },
      { width = 30 },
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

  -- プレビュー: 上半分に README、下半分にコミット履歴を縦に並べる。
  -- コミット履歴のうち未プッシュ (@{u}..HEAD) のものは緑 + ↑ で強調する。
  --
  -- termopen (端末) ではなく buffer previewer を使う。理由は折り返し制御:
  -- termopen は幅を超える行を端末が必ず物理折り返しし、しかも bat は全角を
  -- 正しく折り返せないため、README の長さで「commits」見出しの位置がずれてしまう。
  -- buffer previewer なら wrap=false で 1 論理行 = 1 表示行が保証され、
  -- nvim_buf_set_lines で行数を完全に固定できる。
  --
  -- 変数名は `repo` にする。zsh では `path` が $PATH に連動する特殊変数のため、
  -- `path=$1` とすると PATH が引数のディレクトリだけに上書きされ git が消える。
  -- `]==]` で囲い、内部の zsh の [[ ]] や @{u} と Lua 長括弧が衝突しないようにする。
  local PREVIEW_SCRIPT = [==[
repo=$1
# プレビューウィンドウの高さと半分の行数を Lua 側から受け取る。
half=${2:-20}
height=${3:-40}
# 上半分: README をちょうど half 行に収め、足りない分は空行で埋める (固定レイアウト)。
# 色付けは Lua 側 (markdown treesitter + 手動ハイライト) で行うためプレーンに出す。
readme=""
for f in README.md README.markdown README.rst README README.txt; do
  [[ -f "$repo/$f" ]] && { readme="$repo/$f"; break; }
done
if [[ -n "$readme" ]]; then
  out=$(cat "$readme")
else
  out="(no README)"
fi
out=$(print -r -- "$out" | head -n "$half")
# README を half 行で切ると未閉じのコードブロック (```) が残り、markdown 着色が
# 下のコミット履歴まで波及する。``` が奇数個なら閉じフェンスを補って構文を閉じる。
# half 行を維持するため、ちょうど half 行のときは最終行を閉じフェンスに差し替える。
if (( $(print -r -- "$out" | grep -c '^```') % 2 == 1 )); then
  if (( $(print -r -- "$out" | wc -l) >= half )); then
    out=$(print -r -- "$out" | head -n $((half - 1)))
  fi
  out="$out"$'\n''```'
fi
print -r -- "$out"
shown=$(print -r -- "$out" | wc -l)
for ((i = shown; i < half; i++)); do echo; done
echo "──────── commits ────────"
# 下: コミット履歴。未プッシュ (@{u}..HEAD) を ↑ 始まりにし、Lua 側で緑に着色する。
# 表示数は残り行数 (height - half - 見出し1行) に制限し、全体を height に収める。
rest=$((height - half - 1))
[[ $rest -lt 1 ]] && rest=1
if git -C "$repo" rev-parse @{u} >/dev/null 2>&1; then
  {
    git -C "$repo" --no-pager log --format="↑ %h %s" @{u}..HEAD
    git -C "$repo" --no-pager log --format="  %h %s" "@{u}"
  } | head -n "$rest"
else
  git -C "$repo" --no-pager log --format="  %h %s" | head -n "$rest"
fi
]==]

  local previewer = previewers.new_buffer_previewer({
    title = "preview",
    define_preview = function(self, entry, status)
      -- telescope のプレビューウィンドウ id は status.layout.preview.winid。
      local win = status and status.layout and status.layout.preview and status.layout.preview.winid
      local valid = win and vim.api.nvim_win_is_valid(win)
      local height = valid and vim.api.nvim_win_get_height(win) or 40
      local width = valid and vim.api.nvim_win_get_width(win) or 80
      local half = math.max(5, math.floor(height / 2) - 1)
      local bufnr = self.state.bufnr

      local out = vim.fn.systemlist({
        "zsh", "-c", PREVIEW_SCRIPT, "_", entry.path, tostring(half), tostring(height),
      })

      -- 折り返しでレイアウトが崩れないよう、各行を表示幅 width に切り詰める。
      -- wrap 設定に依存せず 1 行 = 1 表示行を保証する (これが固定レイアウトの要)。
      local function clip(s)
        if vim.fn.strdisplaywidth(s) <= width then
          return s
        end
        local lo, hi = 0, vim.fn.strchars(s)
        while lo < hi do
          local mid = math.floor((lo + hi + 1) / 2)
          if vim.fn.strdisplaywidth(vim.fn.strcharpart(s, 0, mid)) <= width then
            lo = mid
          else
            hi = mid - 1
          end
        end
        return vim.fn.strcharpart(s, 0, lo)
      end
      local lines = {}
      for i, l in ipairs(out) do
        lines[i] = clip(l)
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- README を markdown として treesitter 着色する (着色内容は変更しない)。
      vim.bo[bufnr].filetype = "markdown"
      if valid then
        vim.wo[win].wrap = false
      end
      -- コミット履歴部分のみ手動着色する (README の着色には触れない)。
      -- 未プッシュ (↑) を緑、見出しを強調、プッシュ済みのハッシュを淡色にする。
      for i, l in ipairs(lines) do
        if l:match("^↑") then
          pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "DiagnosticOk", i - 1, 0, -1)
        elseif l:match("^────") then
          pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Title", i - 1, 0, -1)
        elseif l:match("^  %x+ ") then
          pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "Comment", i - 1, 0, 9)
        end
      end
    end,
  })

  pickers
    .new(opts, {
      prompt_title = "ghq repositories",
      -- 検索入力ではなく j/k で選択できるよう normal モードで起動する (検索は i で開始)。
      initial_mode = "normal",
      finder = finders.new_async_job({
        command_generator = function()
          return { "zsh", "-c", LIST_SCRIPT }
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
          -- 選択リポジトリへ移動する。
          vim.cmd.cd(vim.fn.fnameescape(entry.path))
        end)
        return true
      end,
    })
    :find()
end

return M
