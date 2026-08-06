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

      -- terminal-browser CLI のペイン検出は nvim (タイトルを書き換え続ける TUI) 配下で必ず失敗するため CDP 直結を使う
      local function agent_browser_bin()
        local bin = vim.fn.expand("~/.local/share/terminal-browser/app/agent-browser/bin/agent-browser")
        return vim.fn.executable(bin) == 1 and bin or nil
      end

      -- vim.fn.* は fast event context で呼べないため、コールバックから使う値は起動時に解決しておく
      local BIN = terminal_browser_bin()
      local AGENT = agent_browser_bin()

      local float_win = {
        position = "float",
        width = 0.95,
        height = 0.95,
        border = "rounded",
      }

      local SCROLL_STEP = 120
      local SCROLL_PAGE = 480

      local term ---@type snacks.win?
      local ports_by_buf = {} ---@type table<integer, integer> buf -> CDP ポート
      local viewport_by_buf = {} ---@type table<integer, { w: number, h: number }>

      local function alive()
        return term ~= nil and term:buf_valid()
      end

      local function warn(message)
        vim.schedule(function()
          vim.notify(message, vim.log.levels.WARN)
        end)
      end

      local function buf_terminal_info(buf)
        local chan = vim.bo[buf].channel
        local ok, info = pcall(vim.api.nvim_get_chan_info, chan)
        if not ok then
          return nil, nil
        end
        local ok_pid, pid = pcall(vim.fn.jobpid, chan)
        return info.pty, ok_pid and pid or nil
      end

      -- CLI の ls はペイン検出のリトライで数秒かかるため、Electron の起動スイッチから直接ポートを読む
      local function resolve_port(bin, buf, cb, quiet)
        if ports_by_buf[buf] then
          return cb(ports_by_buf[buf])
        end
        local function take(port)
          ports_by_buf[buf] = port
          cb(port)
        end
        local tty = buf_terminal_info(buf)
        vim.system({ "ps", "-Ao", "command=" }, { text = true }, function(ps)
          local ports = {}
          for port in (ps.stdout or ""):gmatch("remote%-debugging%-port=(%d+)") do
            ports[tonumber(port)] = true
          end
          local found = vim.tbl_keys(ports)
          if #found == 1 then
            return take(found[1])
          end
          -- ポート不在でコマンドを投げると agent-browser が自前でブラウザを起動しにいく
          if #found == 0 then
            return quiet or warn("terminal-browser: 起動中のブラウザが見つかりません")
          end
          -- 複数の Electron が動いている等で一意に決まらない場合だけ、遅くても確実な ls に頼る
          vim.system({ bin, "ls", "--all", "--json" }, { text = true }, function(res)
            local ok, data = pcall(vim.json.decode, res.stdout or "")
            local browsers = ok and type(data) == "table" and data.browsers or {}
            for _, browser in ipairs(browsers) do
              if browser.cdpPort and (browser.tty == tty or #browsers == 1) then
                return take(browser.cdpPort)
              end
            end
            warn(
              ("terminal-browser: CDP ポート特定に失敗 (ps 候補=%d pty=%s ls 候補=%d)"):format(
                #found,
                tostring(tty),
                #browsers
              )
            )
          end)
        end)
      end

      ---@param args string[] agent-browser のコマンドと引数
      ---@param cb? fun(stdout: string)
      ---@param quiet? boolean マウス等の高頻度操作は失敗しても黙らせる
      local function action(buf, args, cb, quiet)
        if not BIN or not AGENT then
          return quiet or warn("terminal-browser: agent-browser が見つかりません")
        end
        resolve_port(BIN, buf, function(port)
          local cmd = vim.list_extend({ AGENT, "--cdp", tostring(port) }, args)
          vim.system(cmd, { text = true }, function(res)
            if res.code ~= 0 then
              -- ブラウザが落ちた後はポートが変わるため、失敗したら引き直させる
              ports_by_buf[buf] = nil
              viewport_by_buf[buf] = nil
              if quiet then
                return
              end
              return warn(
                ("terminal-browser: %s 失敗 (code=%s) %s"):format(
                  table.concat(args, " "),
                  tostring(res.code),
                  vim.trim(res.stderr or "")
                )
              )
            end
            if cb then
              cb(res.stdout or "")
            end
          end)
        end, quiet)
      end

      -- CDP の Target.createTarget は Electron 非対応なので、ページ側の window.open でタブを作る
      local function new_tab(buf, url)
        action(buf, { "eval", ("window.open(%q,'_blank')"):format(url or "about:blank") }, function()
          action(buf, { "tab", "list" }, function(stdout)
            local n = select(2, stdout:gsub("%[t%d+%]", ""))
            vim.schedule(function()
              vim.notify("terminal-browser: タブ " .. n .. " 枚")
            end)
          end)
        end)
      end

      -- 現在タブは直前に → が付き、id は t1 形式 (裸の数値は不可)。改行が \n とは限らないため行分割に頼らない
      local function each_tab(buf, cb)
        action(buf, { "tab", "list" }, function(stdout)
          local ids, current = {}, nil
          for prefix, id in stdout:gmatch("([^%[]*)%[(t%d+)%]") do
            ids[#ids + 1] = id
            if prefix:find("→", 1, true) then
              current = #ids
            end
          end
          cb(ids, current, stdout)
        end)
      end

      local function switch_tab(buf, delta)
        each_tab(buf, function(ids, current, raw)
          if not current or #ids < 2 then
            return warn("terminal-browser: 切替先なし (認識タブ=" .. #ids .. ")\n" .. vim.trim(raw))
          end
          action(buf, { "tab", ids[(current - 1 + delta) % #ids + 1] })
        end)
      end

      -- 最後の 1 枚は agent-browser が閉じるのを拒むため、手前で止めて余計なエラーを出さない
      local function close_tab(buf)
        each_tab(buf, function(ids, _, raw)
          if #ids < 2 then
            return warn(
              "terminal-browser: 最後のタブは閉じられません (認識タブ="
                .. #ids
                .. ")\n"
                .. vim.trim(raw)
            )
          end
          action(buf, { "tab", "close" })
        end)
      end

      -- ドットを含むだけでは URL と断定できない (lua string.format 等) ため、既知 TLD かパス付きに限る
      local KNOWN_TLD = {}
      for tld in
        ("com net org io dev jp co uk ai app sh me gg to xyz cloud tv info so fm ly rs page site local"):gmatch("%S+")
      do
        KNOWN_TLD[tld] = true
      end

      local function resolve_target(input)
        local text = vim.trim(input)
        if text:match("^%a[%w+.-]*://") then
          return text
        end
        if text:match("^localhost[:/]?") and not text:find("%s") then
          return "http://" .. text
        end
        if not text:find("%s") then
          local host = (text:match("^([^/?#]+)") or ""):gsub(":%d+$", "")
          local tld = host:match("%.([%a]+)%.?$")
          if tld and KNOWN_TLD[tld:lower()] then
            return "https://" .. text
          end
        end
        return "https://www.google.com/search?q=" .. vim.uri_encode(text)
      end

      local function prompt_new_tab(buf)
        vim.ui.input({ prompt = "検索 or URL: " }, function(input)
          if not input or vim.trim(input) == "" then
            return
          end
          new_tab(buf, resolve_target(input))
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

      -- ページ座標はセル位置の比で求める。ビューポートは CSS px なのでリサイズで変わる
      local function with_viewport(buf, cb)
        local cached = viewport_by_buf[buf]
        if cached then
          return cb(cached)
        end
        action(buf, { "eval", "JSON.stringify({w:innerWidth,h:innerHeight})" }, function(stdout)
          local json = stdout:match("{.-}")
          local ok, size = pcall(vim.json.decode, json or "")
          if ok and size and size.w and size.h then
            viewport_by_buf[buf] = size
            cb(size)
          end
        end, true)
      end

      local function mouse_page_pos(buf, cb)
        local pos = vim.fn.getmousepos()
        local win = pos.winid
        if win == 0 or not vim.api.nvim_win_is_valid(win) then
          return
        end
        local cols = vim.api.nvim_win_get_width(win)
        local rows = vim.api.nvim_win_get_height(win)
        with_viewport(buf, function(size)
          local x = math.floor((pos.wincol - 0.5) / cols * size.w)
          local y = math.floor((pos.winrow - 0.5) / rows * size.h)
          cb(math.max(0, x), math.max(0, y))
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
        ["t"] = {
          run = function(buf)
            prompt_new_tab(buf)
          end,
          desc = "新規タブ (検索 or URL)",
        },
        ["x"] = { run = close_tab, desc = "タブを閉じる" },
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
      local attached = {} ---@type table<integer, true>
      local wants_insert = {} ---@type table<integer, true> i で明示的に入力モードへ入ったか
      local function attach_control_mode(win)
        local buf = type(win) == "table" and win.buf or win
        if not buf or attached[buf] or not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        attached[buf] = true
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
            action(buf, { "tab", "t" .. n })
          end, n .. " 番タブへ")
        end
        -- マウスは normal モードで捕まえて CDP へ流す。terminal モードへ落とさないための要
        local MOUSE = {
          ["<LeftMouse>"] = { { "mouse", "down" }, desc = "クリック" },
          ["<LeftRelease>"] = { { "mouse", "up" }, desc = "クリック解除" },
          ["<LeftDrag>"] = { desc = "ドラッグ" },
          ["<RightMouse>"] = { { "mouse", "down", "right" }, desc = "右クリック" },
          ["<RightRelease>"] = { { "mouse", "up", "right" }, desc = "右クリック解除" },
        }
        for key, spec in pairs(MOUSE) do
          map(key, function()
            mouse_page_pos(buf, function(x, y)
              action(buf, { "mouse", "move", tostring(x), tostring(y) }, function()
                if spec[1] then
                  action(buf, spec[1], nil, true)
                end
              end, true)
            end)
          end, spec.desc)
        end
        for key, dy in pairs({ ["<ScrollWheelDown>"] = SCROLL_STEP, ["<ScrollWheelUp>"] = -SCROLL_STEP }) do
          map(key, function()
            action(buf, { "mouse", "wheel", tostring(dy) }, nil, true)
          end, "ホイール")
        end

        -- 割り当てのないキーが vim の編集操作に漏れると表示が崩れるため、閉じたモードにする
        local PASS_THROUGH = { [":"] = true, ["<C-w>"] = true, ["<C-c>"] = true }
        -- gg のような多打鍵マッピングは、先頭 1 文字を潰すと発火しなくなる
        local prefixes = {}
        for key in pairs(CONTROL_KEYS) do
          if #key > 1 and not key:match("^<") then
            prefixes[key:sub(1, 1)] = true
          end
        end
        for code = 33, 126 do
          local key = string.char(code)
          if not CONTROL_KEYS[key] and not PASS_THROUGH[key] and not prefixes[key] and not key:match("%d") then
            map(key, "<Nop>", "未割り当て")
          end
        end
        for _, key in ipairs({ "0", "<Up>", "<Down>", "<Left>", "<Right>", "<CR>", "<BS>", "<Space>", "<Tab>" }) do
          if not CONTROL_KEYS[key] then
            map(key, "<Nop>", "未割り当て")
          end
        end

        map("?", show_help, "キー一覧")
        map("q", function()
          if type(win) == "table" then
            win:hide()
          end
        end, "閉じる")
        map("i", function()
          wants_insert[buf] = true
          vim.cmd.startinsert()
        end, "入力モードへ")
        -- 単発 <Esc> はページ側 (モーダルを閉じる等) に渡したいので二度押しで抜ける
        vim.keymap.set("t", "<Esc><Esc>", function()
          wants_insert[buf] = nil
          vim.cmd.stopinsert()
        end, { buffer = buf, silent = true, desc = "browser: 操作モードへ" })

        -- クリックすると nvim が terminal モードに入り操作キーが死ぬため、i 以外での遷移は差し戻す
        vim.api.nvim_create_autocmd("TermEnter", {
          buffer = buf,
          callback = function()
            if not wants_insert[buf] then
              vim.schedule(function()
                if vim.api.nvim_get_current_buf() == buf and not wants_insert[buf] then
                  vim.cmd.stopinsert()
                end
              end)
            end
          end,
        })

        vim.api.nvim_create_autocmd("BufWipeout", {
          buffer = buf,
          callback = function()
            ports_by_buf[buf] = nil
            attached[buf] = nil
            wants_insert[buf] = nil
            viewport_by_buf[buf] = nil
          end,
        })

        vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
          callback = function()
            viewport_by_buf[buf] = nil
          end,
        })
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == buf then
            vim.cmd.stopinsert()
          end
        end)
      end

      -- 開き方によらず取りこぼさないよう、terminal-browser を走らせる端末バッファ全てに付ける
      vim.api.nvim_create_autocmd("TermOpen", {
        callback = function(args)
          if vim.api.nvim_buf_get_name(args.buf):match("terminal%-browser") then
            attach_control_mode(args.buf)
          end
        end,
      })

      local function open_float(url)
        local bin = BIN
        if not bin then
          return false
        end
        if alive() then
          term:show()
          if url and url ~= "" then
            new_tab(term.buf, url)
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
        local bin = BIN
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

      vim.api.nvim_create_user_command("TerminalBrowserDebug", function()
        local buf = vim.api.nvim_get_current_buf()
        local lines = {
          "buf=" .. buf .. " name=" .. vim.api.nvim_buf_get_name(buf),
          "cached_port=" .. tostring(ports_by_buf[buf]),
          "BIN=" .. tostring(BIN) .. " AGENT=" .. tostring(AGENT),
        }
        vim.system({ "ps", "-Ao", "command=" }, { text = true }, function(ps)
          local ports = {}
          for port in (ps.stdout or ""):gmatch("remote%-debugging%-port=(%d+)") do
            ports[tonumber(port)] = true
          end
          lines[#lines + 1] = "ps ports=" .. vim.inspect(vim.tbl_keys(ports))
          action(buf, { "tab", "list" }, function(stdout)
            lines[#lines + 1] = "tab list:\n" .. vim.trim(stdout)
            vim.schedule(function()
              vim.notify(table.concat(lines, "\n"))
            end)
          end)
        end)
      end, { desc = "terminal-browser の解決状態を表示" })

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
