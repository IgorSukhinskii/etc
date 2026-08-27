-- Markdown reading/writing experience: render-markdown.nvim + buffer-local
-- ergonomics. Colors are deliberately left to render-markdown's defaults so
-- they derive from the active tinted (base16) highlight groups.

local rm = require("render-markdown")

rm.setup({
  file_types = { "markdown", "codecompanion", "Avante" },
  -- Render everything except the line the cursor is on, so editing shows raw
  -- syntax while reading stays clean.
  anti_conceal = { enabled = true, above = 0, below = 0 },
  render_modes = { "n", "c", "t" },

  heading = {
    sign = false,
    position = "inline",
    icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
    width = "block",
    min_width = 60,
    left_pad = 0,
    right_pad = 2,
    border = true,
    border_virtual = true,
    above = "▄",
    below = "▀",
  },

  paragraph = { left_margin = 0 },

  code = {
    sign = false,
    style = "full",
    position = "right",
    width = "block",
    min_width = 60,
    left_pad = 2,
    right_pad = 2,
    language_pad = 2,
    border = "thick",
    above = "▄",
    below = "▀",
  },

  dash = { width = "full", icon = "─" },

  bullet = {
    icons = { "●", "○", "◆", "◇" },
    right_pad = 1,
  },

  checkbox = {
    unchecked = { icon = "󰄱 " },
    checked = { icon = "󰱒 ", scope_highlight = "@markup.strikethrough" },
    custom = {
      todo = { raw = "[-]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
      cancelled = {
        raw = "[~]",
        rendered = "󰰱 ",
        highlight = "RenderMarkdownError",
        scope_highlight = "@markup.strikethrough",
      },
      important = { raw = "[!]", rendered = "󰀪 ", highlight = "RenderMarkdownWarn" },
    },
  },

  quote = { icon = "▋", repeat_linebreak = true },

  pipe_table = {
    preset = "round",
    alignment_indicator = "┅",
    -- Subtract concealed/empty space from width calculation so tables full of
    -- links stay as narrow as they look.
    cell = "trimmed",
  },

  link = {
    image = "󰥶 ",
    email = "󰀓 ",
    hyperlink = "󰌷 ",
    wiki = { icon = "󱗖 ", body = function(ctx) return ctx.text end },
    custom = {
      github = { pattern = "github%.com", icon = "󰊤 " },
      gitlab = { pattern = "gitlab%.com", icon = "󰮠 " },
      neovim = { pattern = "neovim%.io", icon = " " },
      python = { pattern = "%.py$", icon = "󰌠 " },
      nix = { pattern = "%.nix$", icon = "󱄅 " },
    },
  },

  -- Needs `latex2text` (pylatexenc) on PATH; off by default to avoid errors.
  latex = { enabled = false },

  -- Reading-friendly window options while rendering is active.
  win_options = {
    conceallevel = { default = vim.o.conceallevel, rendered = 3 },
    concealcursor = { default = vim.o.concealcursor, rendered = "" },
    showbreak = { default = "", rendered = "  " },
    breakindent = { default = false, rendered = true },
    breakindentopt = { default = "", rendered = "" },
  },

  completions = {
    blink = { enabled = true },
    lsp = { enabled = true },
  },
})

vim.keymap.set("n", "<leader>mr", "<Cmd>RenderMarkdown buf_toggle<CR>", { desc = "Toggle markdown rendering" })
vim.keymap.set("n", "<leader>me", "<Cmd>RenderMarkdown expand<CR>", { desc = "Expand markdown render range" })
vim.keymap.set("n", "<leader>mc", "<Cmd>RenderMarkdown contract<CR>", { desc = "Contract markdown render range" })

-- Buffer-local prose ergonomics. The global shiftwidth/tabstop of 8 makes
-- nested markdown lists unreadable and breaks list continuation.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text", "gitcommit" },
  callback = function(args)
    local o = vim.opt_local
    o.shiftwidth = 2
    o.tabstop = 2
    o.softtabstop = 2
    o.wrap = true
    o.linebreak = true
    o.breakindent = true
    o.spell = true
    o.spelllang = { "en_us" }
    o.cursorline = true
    o.signcolumn = "no"
    -- Move by screen line when wrapped.
    for _, lhs in ipairs({ "j", "k" }) do
      vim.keymap.set({ "n", "x" }, lhs, function()
        return vim.v.count == 0 and ("g" .. lhs) or lhs
      end, { buffer = args.buf, expr = true, desc = "Move by display line" })
    end
  end,
})

-- "Zen" reading toggle: centre the prose column and drop the chrome.
local zen = {}
vim.keymap.set("n", "<leader>mz", function()
  local win = vim.api.nvim_get_current_win()
  local saved = zen[win]
  if saved then
    zen[win] = nil
    for opt, value in pairs(saved) do
      vim.api.nvim_set_option_value(opt, value, { win = win })
    end
    return
  end
  local o = { "number", "relativenumber", "list", "colorcolumn", "foldcolumn" }
  saved = {}
  for _, opt in ipairs(o) do
    saved[opt] = vim.api.nvim_get_option_value(opt, { win = win })
  end
  zen[win] = saved
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].list = false
  vim.wo[win].colorcolumn = ""
  vim.wo[win].foldcolumn = "8"
end, { desc = "Toggle markdown zen reading" })

-- Wide tables: GFM cannot wrap a cell in source, so wrapping is view-only.
-- Rendering happens on demand (auto_preview = false) to avoid fighting
-- render-markdown's own pipe_table renderer.
local ok_tw, table_wrap = pcall(require, "markdown-table-wrap")
if ok_tw then
  table_wrap.setup({
    auto_preview = false,
    preview_mode = "float",
    fit_to_window = true,
    max_width_ratio = 0.9,
    min_col_width = 8,
    max_col_width = 50,
    table_border = "rounded",
    row_separator = true,
    highlight_preset = "render_markdown",
    reader = {
      auto_open = "has_table", -- only consulted when auto_preview is on
      wrap = true,
      breakindent = true,
      conceallevel = 2,
    },
  })
  vim.keymap.set("n", "<leader>mt", "<Cmd>MarkdownTableFloatPreview<CR>", { desc = "Float wrapped table under cursor" })
  vim.keymap.set("n", "<leader>mR", "<Cmd>MarkdownTableToggleReader<CR>", { desc = "Toggle wrapped-table reader" })
  -- Inline mode draws over the table itself, so render-markdown's own
  -- renderer has to step aside for the buffer while it is active.
  vim.keymap.set("n", "<leader>mI", function()
    vim.cmd("RenderMarkdown buf_toggle")
    vim.cmd("MarkdownTableToggleInline")
  end, { desc = "Toggle inline wrapped tables" })
end

local img_clip = package.loaded["img-clip"] or (pcall(require, "img-clip") and require("img-clip"))
if img_clip then
  img_clip.setup({
    default = {
      dir_path = "assets",
      relative_to_current_file = true,
      prompt_for_file_name = true,
      drag_and_drop = { insert_mode = true },
    },
  })
  vim.keymap.set("n", "<leader>mp", "<Cmd>PasteImage<CR>", { desc = "Paste image from clipboard" })
end
