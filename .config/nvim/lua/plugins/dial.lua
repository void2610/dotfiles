return {
  {
    "monaqa/dial.nvim",
    keys = {
      {
        "<C-a>",
        function() return require("dial.map").inc_normal() end,
        expr = true,
        desc = "Increment",
      },
      {
        "<C-x>",
        function() return require("dial.map").dec_normal() end,
        expr = true,
        desc = "Decrement",
      },
      {
        "g<C-a>",
        function() return require("dial.map").inc_gnormal() end,
        expr = true,
        desc = "Increment (additive)",
      },
      {
        "g<C-x>",
        function() return require("dial.map").dec_gnormal() end,
        expr = true,
        desc = "Decrement (additive)",
      },
      {
        "<C-a>",
        function() return require("dial.map").inc_visual() end,
        mode = "v",
        expr = true,
        desc = "Increment",
      },
      {
        "<C-x>",
        function() return require("dial.map").dec_visual() end,
        mode = "v",
        expr = true,
        desc = "Decrement",
      },
      {
        "g<C-a>",
        function() return require("dial.map").inc_gvisual() end,
        mode = "v",
        expr = true,
        desc = "Increment (additive)",
      },
      {
        "g<C-x>",
        function() return require("dial.map").dec_gvisual() end,
        mode = "v",
        expr = true,
        desc = "Decrement (additive)",
      },
    },
    config = function()
      local augend = require("dial.augend")
      require("dial.config").augends:register_group({
        default = {
          augend.integer.alias.decimal_int,
          augend.integer.alias.hex,
          augend.integer.alias.binary,
          augend.date.alias["%Y/%m/%d"],
          augend.date.alias["%Y-%m-%d"],
          augend.date.alias["%m/%d"],
          augend.date.alias["%H:%M"],
          augend.constant.alias.bool,
          augend.semver.alias.semver,
          augend.constant.new({ elements = { "and", "or" }, word = true, cyclic = true }),
          augend.constant.new({ elements = { "&&", "||" }, word = false, cyclic = true }),
          augend.constant.new({ elements = { "True", "False" }, word = true, cyclic = true }),
        },
      })
    end,
  },
}
