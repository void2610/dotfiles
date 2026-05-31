-- gitcommit バッファを 1 キーで保存終了 (= コミット確定) できるようにする。
-- lazygit の C (claude 生成メッセージ) で開かれる git commit -e を素早く確定するため。
vim.keymap.set("n", "q", "<cmd>wq<cr>", { buffer = true, desc = "保存してコミット確定" })
