-- マウス押下位置 (ドラッグ選択の起点として <LeftDrag> 側で使う)
local mouse_origin

return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- ドラッグ追跡 (?1002h/?1003h) だけ落とす。Claude Code の選択実装は改行を NUL に化けさせるため使わず、
      -- ホイール (?1000h) は残して Claude Code 側の仮想スクロールを生かす (alt screen でバッファに履歴が残らないため)
      env = {
        CLAUDE_CODE_DISABLE_MOUSE_CLICKS = "1",
      },
      diff_opts = {
        open_in_new_tab = true,
      },
      terminal = {
        split_side = "right",
        split_width_percentage = 0.4, -- Claude Code のペイン幅
        -- LazyVim が snacks.terminal に設定する `<C-/>` / `<C-_>` の
        -- "hide" バインドを claudecode のターミナルでだけ無効化する。
        -- これらが効くと Claude セッション自体が閉じてしまうため。
        snacks_win_opts = {
          keys = {
            hide_slash = false,
            hide_underscore = false,
            claude_toggle = {
              "<leader>a",
              function()
                vim.cmd("ClaudeCodeFocus")
              end,
              mode = "t",
              desc = "Toggle Claude",
            },
            -- 押下は記録と URL 起動だけ。terminal モードを抜けないので単クリックではホイール (仮想スクロール) が生きたまま
            record_mouse_origin = {
              "<LeftMouse>",
              function()
                local pos = vim.fn.getmousepos()
                mouse_origin = pos
                -- terminal モード中は keymaps.lua の n モード版クリックが効かないため、ここで gx 相当を行う
                local url = require("util.url").at_mouse(pos)
                if url then
                  vim.ui.open(url)
                end
              end,
              mode = "t",
              desc = "Record mouse origin / open URL",
            },
            -- ドラッグ開始時に起点から選択を組み立てる。以降の <LeftDrag> は visual 側の既定動作で伸びる
            start_mouse_select = {
              "<LeftDrag>",
              function()
                local cur = vim.fn.getmousepos()
                local org = mouse_origin or cur
                vim.cmd("stopinsert")
                -- terminal モードからは normal! もカーソル移動もできないためモード遷移後に回す
                vim.schedule(function()
                  -- 連続する <LeftDrag> で選択が張り直されないよう、開始済みなら以降は既定動作に任せる
                  if vim.api.nvim_get_mode().mode:find("^[vV\22]") then
                    return
                  end
                  if org.winid ~= 0 and org.line > 0 then
                    pcall(vim.api.nvim_win_set_cursor, org.winid, { org.line, math.max(org.column - 1, 0) })
                  end
                  vim.cmd("normal! v")
                  if cur.winid ~= 0 and cur.line > 0 then
                    pcall(vim.api.nvim_win_set_cursor, cur.winid, { cur.line, math.max(cur.column - 1, 0) })
                  end
                end)
              end,
              mode = "t",
              desc = "Start mouse selection",
            },
            -- visual に入った後のドラッグはカーソルを追従させて選択を伸ばす
            extend_mouse_select = {
              "<LeftDrag>",
              function()
                local cur = vim.fn.getmousepos()
                if cur.winid ~= 0 and cur.line > 0 then
                  pcall(vim.api.nvim_win_set_cursor, cur.winid, { cur.line, math.max(cur.column - 1, 0) })
                end
              end,
              mode = "x",
              desc = "Extend mouse selection",
            },
            -- マウスを離した時点でヤンクする (Claude Code 本来のマウスコピーと同じ操作数に保つ)
            copy_on_mouse_release = {
              "<LeftRelease>",
              function()
                local sv, cv = vim.fn.getpos("v"), vim.fn.getpos(".")
                -- 単クリックでもヤンク経由で抜ける (v で抜けると後続の startinsert が届かない)。レジスタは戻す
                local empty = sv[2] == cv[2] and sv[3] == cv[3]
                local unnamed, regtype, plus
                if empty then
                  unnamed, regtype, plus = vim.fn.getreg('"'), vim.fn.getregtype('"'), vim.fn.getreg("+")
                end
                vim.cmd("normal! y")
                if empty then
                  vim.fn.setreg('"', unnamed, regtype)
                  vim.fn.setreg("+", plus)
                end
                vim.cmd("startinsert")
              end,
              mode = "x",
              desc = "Copy selection on mouse release",
            },
          },
        },
      },
    },
    keys = {
      { "<leader>a", "<cmd>ClaudeCodeFocus<cr>", desc = "Toggle/Focus Claude" },
      { "<leader>A", nil, desc = "AI/Claude Code" },
      {
        "<leader>An",
        function()
          -- claudecode.nvim 本体のリグレッションを避けるため、特定バージョンの CLI を npx で起動する
          local term = require("claudecode.terminal")
          local pinned = "npx @anthropic-ai/claude-code@2.1.145"
          term.setup({}, pinned, nil)
          term.focus_toggle({}, nil)
          -- 後続の <leader>a が既定の `claude` を使えるよう復元する (起動済みターミナルには影響しない)
          term.setup({}, nil, nil)
        end,
        desc = "Focus Claude (pinned npx 2.1.154)",
      },
      { "<leader>Af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
      { "<leader>Ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
      { "<leader>AC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
      { "<leader>Am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
      { "<leader>Ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
      { "<leader>As", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
      {
        "<leader>As",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
      },
      { "<leader>Aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
      { "<leader>Ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
    },
  },
}
