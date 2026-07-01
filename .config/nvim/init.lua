vim.scriptencoding = "utf-8"
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"

-- プラグインの cwd 変更より前に、nvim を起動したディレクトリを記録しておく
vim.g.launch_cwd = vim.fn.getcwd()

vim.wo.number = true

if vim.loader then
  vim.loader.enable()
end

require("config.lazy")
