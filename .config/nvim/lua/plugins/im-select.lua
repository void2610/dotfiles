return {
  {
    "keaising/im-select.nvim",
    event = "VeryLazy",
    opts = {
      -- macOS では macism を入力ソースの取得・切替に使用する
      default_command = "macism",
      -- ノーマルモードへ戻る際に切り替える入力ソース（英数）
      default_im_select = "com.apple.keylayout.ABC",
      -- インサートモードへ入るタイミングで前回の入力ソースを復元する
      set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
      set_previous_events = { "InsertEnter" },
    },
  },
}
