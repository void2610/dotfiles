return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      -- progress (Top/Bot/xx%)の前に総行数を挿入
      local total_lines = {
        function()
          return vim.api.nvim_buf_line_count(0)
        end,
      }
      for _, section in pairs(opts.sections or {}) do
        for i, comp in ipairs(section) do
          if comp == "progress" or (type(comp) == "table" and comp[1] == "progress") then
            table.insert(section, i, total_lines)
            break
          end
        end
      end

      -- <c-/> で開いた snacks ターミナルでコマンド実行中なら、最新出力1行を表示する。
      -- シェル直下に子プロセスがいる間だけ「実行中」とみなし、プロンプトに戻れば非表示にする。
      local term_state = { line = "" }

      local function snacks_terminal_buf()
        local ok, snacks = pcall(require, "snacks")
        if not ok or not snacks.terminal then
          return nil
        end
        local terms = snacks.terminal.list()
        local current = vim.api.nvim_get_current_buf()
        for _, t in ipairs(terms) do
          if t.buf == current then
            return t.buf
          end
        end
        local latest
        for _, t in ipairs(terms) do
          if t.buf and vim.api.nvim_buf_is_valid(t.buf) then
            latest = t.buf
          end
        end
        return latest
      end

      local function terminal_tail(buf)
        local total = vim.api.nvim_buf_line_count(buf)
        local lo = math.max(0, total - 200)
        local lines = vim.api.nvim_buf_get_lines(buf, lo, total, false)
        for i = #lines, 1, -1 do
          local line = lines[i] or ""
          line = line:gsub("\27%[[%d;?]*[A-Za-z]", "")
          line = line:gsub("[\1-\8\11\12\14-\31\127]", "")
          if line:match("%S") then
            local max = 80
            if vim.api.nvim_strwidth(line) > max then
              line = "…" .. line:sub(-max)
            end
            return line
          end
        end
        return ""
      end

      opts.sections = opts.sections or {}
      opts.sections.lualine_c = opts.sections.lualine_c or {}
      table.insert(opts.sections.lualine_c, {
        function()
          return term_state.line
        end,
        cond = function()
          return term_state.line ~= ""
        end,
        color = { fg = "#7d8590", gui = "italic" },
      })

      -- ターミナル出力は autocmd で拾えないので、タイマーで状態をポーリングする。
      -- pgrep は vim.system で非同期に呼び、UI ブロック (カーソル点滅) を避ける。
      -- 変化があった時だけ redrawstatus してチラつきと負荷を抑える。
      if not vim.g._snacks_term_tail_timer then
        local timer = vim.uv.new_timer()
        if timer then
          local in_flight = false
          timer:start(
            500,
            500,
            vim.schedule_wrap(function()
              if in_flight then
                return
              end
              local buf = snacks_terminal_buf()
              if not buf then
                if term_state.line ~= "" then
                  term_state.line = ""
                  pcall(vim.cmd, "redrawstatus")
                end
                return
              end
              local pid = vim.b[buf].terminal_job_pid
              if not pid or pid <= 0 then
                if term_state.line ~= "" then
                  term_state.line = ""
                  pcall(vim.cmd, "redrawstatus")
                end
                return
              end
              in_flight = true
              vim.system({ "pgrep", "-P", tostring(pid) }, { text = true }, function(obj)
                in_flight = false
                local running = obj.code == 0 and obj.stdout and obj.stdout:match("%S") ~= nil
                vim.schedule(function()
                  local line = ""
                  if running and vim.api.nvim_buf_is_valid(buf) then
                    line = terminal_tail(buf)
                  end
                  if line ~= term_state.line then
                    term_state.line = line
                    pcall(vim.cmd, "redrawstatus")
                  end
                end)
              end)
            end)
          )
          vim.g._snacks_term_tail_timer = true
        end
      end
    end,
  },
}
