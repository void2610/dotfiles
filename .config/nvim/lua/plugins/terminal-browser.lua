return {
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

      -- gx (netrw 代替) は vim.ui.open を呼ぶため、URL だけ terminal-browser のフロートへ横取りする
      local fallback = vim.ui.open
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.ui.open = function(path, opts)
        local bin = type(path) == "string" and path:match("^https?://") and terminal_browser_bin()
        if not bin then
          return fallback(path, opts)
        end
        Snacks.terminal.open({ bin, "open", path }, {
          win = {
            position = "float",
            width = 0.95,
            height = 0.95,
            border = "rounded",
          },
        })
      end
    end,
  },
}
