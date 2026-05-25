vim.scriptencoding = "utf-8"
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"

vim.wo.number = true

if vim.loader then
  vim.loader.enable()
end

require("config.lazy")
