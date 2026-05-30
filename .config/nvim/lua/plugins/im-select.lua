return {
  {
    "keaising/im-select.nvim",
    event = "VeryLazy",
    opts = {
      -- macOS では macism を入力ソースの取得・切替に使用する
      default_command = "macism",
      -- ノーマルモードへ戻る際に切り替える入力ソース（英数）
      default_im_select = "com.apple.keylayout.ABC",
      -- InsertLeave で直前の入力ソースを保存しつつ英数へ戻し、
      -- InsertEnter で保存しておいた入力ソース（日本語など）を復元する
      set_default_events = { "InsertLeave", "CmdlineLeave" },
      set_previous_events = { "InsertEnter" },
    },
    config = function(_, opts)
      require("im_select").setup(opts)

      -- インサート以外のモードで日本語入力になっている場合に英数へ戻す。
      -- ローマ字 IME は母音入力で即座に変換を開始してキーを奪うため、その間
      -- Neovim にはキーが届かず autocmd が発火しない。よってキー入力とは独立
      -- した uv タイマーで監視する。過去の不具合を踏まえ以下を満たす:
      -- ・FocusLost/FocusGained でフォーカスを監視し、nvim にフォーカスが
      --   ある時だけ切り替える（他アプリの日本語入力を妨害しない）
      -- ・vim.system による非同期実行で UI をブロックしない（カーソル点滅対策）
      -- ・im_select 本体の保存状態には触れないため InsertEnter での復元と干渉しない
      local default_im = opts.default_im_select
      local focused = true
      local grp = vim.api.nvim_create_augroup("im-select-force-eisu", { clear = true })

      vim.api.nvim_create_autocmd("FocusGained", {
        group = grp,
        callback = function()
          focused = true
        end,
      })
      vim.api.nvim_create_autocmd("FocusLost", {
        group = grp,
        callback = function()
          focused = false
        end,
      })

      local timer = vim.uv.new_timer()
      timer:start(
        250,
        250,
        vim.schedule_wrap(function()
          if not focused then
            return
          end
          local mode = vim.api.nvim_get_mode().mode
          -- インサート(i)系・コマンドライン(c)系は対象外
          -- （コマンドラインは日本語検索などで日本語入力を使うため）
          if mode:find("^[ic]") then
            return
          end
          vim.system({ "macism" }, { text = true }, function(res)
            local cur = vim.trim(res.stdout or "")
            if cur ~= "" and cur ~= default_im then
              vim.system({ "macism", default_im })
            end
          end)
        end)
      )

      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = grp,
        callback = function()
          if timer and not timer:is_closing() then
            timer:stop()
            timer:close()
          end
        end,
      })
    end,
  },
}
