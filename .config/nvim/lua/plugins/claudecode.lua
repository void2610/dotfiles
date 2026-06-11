return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
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
                vim.cmd("ClaudeCode")
              end,
              mode = "t",
              desc = "Toggle Claude",
            },
          },
        },
      },
    },
    keys = {
      { "<leader>a", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
      { "<leader>A", nil, desc = "AI/Claude Code" },
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
