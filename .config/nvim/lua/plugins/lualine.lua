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
    end,
  },
}
