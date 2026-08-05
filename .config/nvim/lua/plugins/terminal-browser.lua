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

      local term ---@type snacks.win?

      local function alive()
        return term ~= nil and term:buf_valid()
      end

      local function float_tty()
        if not alive() then
          return nil
        end
        local chan = vim.bo[term.buf].channel
        local ok, info = pcall(vim.api.nvim_get_chan_info, chan)
        return ok and info.pty or nil
      end

      local function warn(message)
        vim.schedule(function()
          vim.notify(message, vim.log.levels.WARN)
        end)
      end

      -- 既存フロートのセッションを ls --json の tty 一致で特定し、新規タブで URL を開く
      local function open_in_existing(bin, url)
        local tty = float_tty()
        if not tty then
          return warn("terminal-browser のセッションを特定できませんでした")
        end
        vim.system({ bin, "ls", "--all", "--json" }, { text = true }, function(res)
          local ok, data = pcall(vim.json.decode, res.stdout or "")
          local key
          if ok and type(data) == "table" then
            for _, browser in ipairs(data.browsers or {}) do
              if browser.tty == tty then
                key = browser.key
                break
              end
            end
          end
          if not key then
            return warn("terminal-browser のセッションを特定できませんでした")
          end
          vim.system({ bin, "action", "--browser", key, "--", "tab", "new" }, { text = true }, function()
            vim.system({ bin, "action", "--browser", key, "--", "open", url }, { text = true }, function(open_res)
              if open_res.code ~= 0 then
                warn("URL を開けませんでした: " .. url)
              end
            end)
          end)
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
            open_in_existing(bin, url)
          end
          return true
        end
        local cmd = { bin, "open" }
        if url and url ~= "" then
          table.insert(cmd, url)
        end
        term = Snacks.terminal.open(cmd, { win = float_win })
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
        if args.args == "" then
          toggle()
        elseif not open_float(args.args) then
          vim.notify("terminal-browser が見つかりません", vim.log.levels.ERROR)
        end
      end, { nargs = "?", desc = "terminal-browser をフロートで開閉" })

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
