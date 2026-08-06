return {
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.providers = vim.tbl_extend("force", opts.sources.providers or {}, {
        cmd_alias = { module = "util.blink_cmd_alias", name = "cmd" },
      })
      opts.cmdline = opts.cmdline or {}
      opts.cmdline.sources = vim.list_extend(opts.cmdline.sources or { "buffer", "cmdline" }, { "cmd_alias" })
    end,
  },
  {
    "folke/snacks.nvim",
    init = function()
      -- ~/.local/bin が nvim の PATH に無い環境でも動くよう実体パスへフォールバックする
      local function terminal_browser_bin()
        if vim.fn.executable("terminal-browser") == 1 then
          return "terminal-browser"
        end
        local local_bin = vim.fn.expand("~/.local/bin/terminal-browser")
        return vim.fn.executable(local_bin) == 1 and local_bin or nil
      end

      local float_win = {
        position = "float",
        width = 0.95,
        height = 0.95,
        border = "rounded",
      }

      local SCROLL_STEP = 120
      local SCROLL_PAGE = 480

      local term ---@type snacks.win?
      local keys_by_buf = {} ---@type table<integer, string> buf -> browser key

      local function alive()
        return term ~= nil and term:buf_valid()
      end

      local function warn(message)
        vim.schedule(function()
          vim.notify(message, vim.log.levels.WARN)
        end)
      end

      local function buf_tty(buf)
        local chan = vim.bo[buf].channel
        local ok, info = pcall(vim.api.nvim_get_chan_info, chan)
        return ok and info.pty or nil
      end

      -- ブラウザは tty で識別する。ペイン情報は TUI 配下で null になることがあり当てにならない
      local function resolve_key(bin, buf, cb)
        if keys_by_buf[buf] then
          return cb(keys_by_buf[buf])
        end
        local tty = buf_tty(buf)
        if not tty then
          return warn("terminal-browser のセッションを特定できませんでした")
        end
        vim.system({ bin, "ls", "--all", "--json" }, { text = true }, function(res)
          local ok, data = pcall(vim.json.decode, res.stdout or "")
          if ok and type(data) == "table" then
            for _, browser in ipairs(data.browsers or {}) do
              if browser.tty == tty then
                keys_by_buf[buf] = browser.key
                return cb(browser.key)
              end
            end
          end
          warn("terminal-browser のセッションを特定できませんでした")
        end)
      end

      ---@param args string[] agent-browser のコマンドと引数
      ---@param cb? fun(stdout: string)
      local function action(buf, args, cb)
        local bin = terminal_browser_bin()
        if not bin then
          return
        end
        resolve_key(bin, buf, function(key)
          local cmd = vim.list_extend({ bin, "action", "--browser", key, "--" }, args)
          vim.system(cmd, { text = true }, function(res)
            if res.code ~= 0 then
              return warn("terminal-browser: " .. table.concat(args, " ") .. " に失敗しました")
            end
            if cb then
              cb(res.stdout or "")
            end
          end)
        end)
      end

      local function open_in_existing(buf, url)
        action(buf, { "tab", "new" }, function()
          action(buf, { "open", url })
        end)
      end

      -- tab list は現在タブの行頭に → が付く。CDP では Target.createTarget が非対応なので必ずこの経路を通す
      local function switch_tab(buf, delta)
        action(buf, { "tab", "list" }, function(stdout)
          local ids, current = {}, nil
          for line in stdout:gmatch("[^\n]+") do
            local id = line:match("%[t(%d+)%]")
            if id then
              ids[#ids + 1] = tonumber(id)
              if line:match("^%s*→") then
                current = #ids
              end
            end
          end
          if not current or #ids < 2 then
            return
          end
          local next_index = (current - 1 + delta) % #ids + 1
          action(buf, { "tab", tostring(ids[next_index]) })
        end)
      end

      local function prompt_open(buf, in_new_tab)
        vim.ui.input({ prompt = "URL: " }, function(url)
          if not url or url == "" then
            return
          end
          if in_new_tab then
            open_in_existing(buf, url)
          else
            action(buf, { "open", url })
          end
        end)
      end

      local function yank_url(buf)
        action(buf, { "get", "url" }, function(stdout)
          local url = vim.trim(stdout)
          vim.schedule(function()
            vim.fn.setreg("+", url)
            vim.notify("yanked: " .. url)
          end)
        end)
      end

      ---@type table<string, { args?: string[], run?: fun(buf: integer), desc: string }>
      local CONTROL_KEYS = {
        ["j"] = { args = { "scroll", "down", tostring(SCROLL_STEP) }, desc = "下スクロール" },
        ["k"] = { args = { "scroll", "up", tostring(SCROLL_STEP) }, desc = "上スクロール" },
        ["<C-d>"] = { args = { "scroll", "down", tostring(SCROLL_PAGE) }, desc = "半ページ下" },
        ["<C-u>"] = { args = { "scroll", "up", tostring(SCROLL_PAGE) }, desc = "半ページ上" },
        ["gg"] = { args = { "eval", "window.scrollTo(0,0)" }, desc = "先頭へ" },
        ["G"] = { args = { "eval", "window.scrollTo(0,document.body.scrollHeight)" }, desc = "末尾へ" },
        ["H"] = { args = { "back" }, desc = "戻る" },
        ["L"] = { args = { "forward" }, desc = "進む" },
        ["r"] = { args = { "reload" }, desc = "リロード" },
        ["t"] = { args = { "tab", "new" }, desc = "新規タブ" },
        ["x"] = { args = { "tab", "close" }, desc = "タブを閉じる" },
        ["<Tab>"] = {
          run = function(buf)
            switch_tab(buf, 1)
          end,
          desc = "次のタブ",
        },
        ["<S-Tab>"] = {
          run = function(buf)
            switch_tab(buf, -1)
          end,
          desc = "前のタブ",
        },
        ["o"] = {
          run = function(buf)
            prompt_open(buf, false)
          end,
          desc = "URL を開く",
        },
        ["O"] = {
          run = function(buf)
            prompt_open(buf, true)
          end,
          desc = "URL を新規タブで開く",
        },
        ["y"] = { run = yank_url, desc = "URL をヤンク" },
      }

      local function show_help()
        local lines = {}
        for key, entry in pairs(CONTROL_KEYS) do
          lines[#lines + 1] = ("  %-8s %s"):format(key, entry.desc)
        end
        table.sort(lines)
        table.insert(lines, 1, "terminal-browser 操作モード")
        vim.list_extend(lines, {
          "  1-9      その番号のタブへ",
          "  i        入力モード (キーをページへ渡す)",
          "  <Esc><Esc> 入力モードを抜ける",
          "  q        閉じる",
        })
        vim.notify(table.concat(lines, "\n"))
      end

      -- nvim の normal / terminal モードをそのままブラウザ操作 / 入力モードとして使う
      local function attach_control_mode(win)
        local buf = win.buf
        local function map(key, fn, desc)
          vim.keymap.set("n", key, fn, { buffer = buf, silent = true, desc = "browser: " .. desc })
        end
        for key, entry in pairs(CONTROL_KEYS) do
          map(key, function()
            if entry.run then
              entry.run(buf)
            else
              action(buf, entry.args)
            end
          end, entry.desc)
        end
        for n = 1, 9 do
          map(tostring(n), function()
            action(buf, { "tab", tostring(n) })
          end, n .. " 番タブへ")
        end
        map("?", show_help, "キー一覧")
        map("q", function()
          win:hide()
        end, "閉じる")
        map("i", function()
          vim.cmd.startinsert()
        end, "入力モードへ")
        -- 単発 <Esc> はページ側 (モーダルを閉じる等) に渡したいので二度押しで抜ける
        vim.keymap.set("t", "<Esc><Esc>", function()
          vim.cmd.stopinsert()
        end, { buffer = buf, silent = true, desc = "browser: 操作モードへ" })

        vim.api.nvim_create_autocmd("BufWipeout", {
          buffer = buf,
          callback = function()
            keys_by_buf[buf] = nil
          end,
        })
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == buf then
            vim.cmd.stopinsert()
          end
        end)
      end

      local function open_float(url)
        local bin = terminal_browser_bin()
        if not bin then
          return false
        end
        if alive() then
          term:show()
          if url and url ~= "" then
            open_in_existing(term.buf, url)
          end
          return true
        end
        local cmd = { bin, "open" }
        if url and url ~= "" then
          table.insert(cmd, url)
        end
        term = Snacks.terminal.open(cmd, { win = float_win })
        attach_control_mode(term)
        return true
      end

      local function open_current(url)
        local bin = terminal_browser_bin()
        if not bin then
          return false
        end
        local cmd = { bin, "open" }
        if url and url ~= "" then
          table.insert(cmd, url)
        end
        attach_control_mode(Snacks.terminal.open(cmd, { win = { position = "current" } }))
        return true
      end

      local function toggle()
        if alive() then
          term:toggle()
        elseif not open_float(nil) then
          vim.notify("terminal-browser が見つかりません", vim.log.levels.ERROR)
        end
      end

      vim.api.nvim_create_user_command("TerminalBrowser", function(args)
        if not open_current(args.args) then
          vim.notify("terminal-browser が見つかりません", vim.log.levels.ERROR)
        end
      end, { nargs = "?", desc = "terminal-browser を現在のウィンドウで開く" })

      -- ユーザーコマンドは大文字始まり必須のため、小文字 :tb は先頭でのみ展開する略語で提供する
      vim.cmd([[cnoreabbrev <expr> tb (getcmdtype() ==# ':' && getcmdpos() == 3) ? 'TerminalBrowser' : 'tb']])

      vim.keymap.set({ "n", "t" }, "<C-=>", toggle, { silent = true, desc = "terminal-browser を開閉" })

      -- gx (netrw 代替) は vim.ui.open を呼ぶため、URL だけ terminal-browser のフロートへ横取りする
      local fallback = vim.ui.open
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.ui.open = function(path, opts)
        if type(path) == "string" and path:match("^https?://") and open_float(path) then
          return
        end
        return fallback(path, opts)
      end
    end,
  },
}
