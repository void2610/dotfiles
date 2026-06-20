return {
  {
    "sphamba/smear-cursor.nvim",
    opts = {
      -- claudecode のターミナルウィンドウでアニメーションさせるために必要
      smear_terminal_mode = true,
    },
    config = function(_, opts)
      require("smear_cursor").setup(opts)

      -- claudecode 以外のターミナル (lazygit 等の snacks_terminal) ではアニメーションを無効化する
      -- smear-cursor 本体が BufEnter で disabled_in_buffer をリセットするため、後勝ちで設定する必要がある
      local group = vim.api.nvim_create_augroup("SmearCursorScope", { clear = true })
      vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function(args)
          if vim.bo[args.buf].buftype ~= "terminal" then return end
          local name = vim.api.nvim_buf_get_name(args.buf)
          if not name:lower():match("claude") then
            require("smear_cursor.animation").disabled_in_buffer = true
          end
        end,
      })
    end,
  },
}
