return {
  -- octo extra の <leader>gr (Octo repo list) は作成順固定で実用性が無いため無効化し、
  -- 本来の <leader>gr を snacks.lua の ghq ランチャーに譲る。
  {
    "pwntester/octo.nvim",
    keys = {
      { "<leader>gr", false },
    },
    config = function(_, opts)
      require("octo").setup(opts)

      -- PR/Issue タイトルに CR/LF が混入すると nvim_buf_set_lines が
      -- "'replacement string' item contains newlines" で失敗するため、
      -- write_title 呼び出し時にタイトルをサニタイズする (upstream バグ回避)。
      local writers = require("octo.ui.writers")
      local original_write_title = writers.write_title
      writers.write_title = function(bufnr, title, line)
        local sanitized = (title or ""):gsub("[\r\n]+", " ")
        return original_write_title(bufnr, sanitized, line)
      end
    end,
  },
}
