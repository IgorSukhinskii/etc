vim.g.mapleader = " "
vim.g.maplocalleader = ","
vim.g.editorconfig = true
vim.g.zig_fmt_autosave = 0

vim.opt.autoindent = true
vim.opt.backup = false
vim.opt.clipboard = "unnamed,unnamedplus"
vim.opt.cmdheight = 1
vim.opt.cursorlineopt = "line"
vim.opt.encoding = "utf-8"
vim.opt.errorbells = false
vim.opt.expandtab = true
vim.opt.hidden = true
vim.opt.ignorecase = false
vim.opt.mouse = "nvi"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.shiftwidth = 8
vim.opt.signcolumn = "yes"
vim.opt.smartcase = false
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.swapfile = false
vim.opt.tabstop = 8
vim.opt.termguicolors = true
vim.opt.tm = 500
vim.opt.updatetime = 300
vim.opt.visualbell = false
vim.opt.wrap = true
vim.opt.writebackup = false

local function has(module)
  local ok, value = pcall(require, module)
  if ok then
    return value
  end
end

local schemes = vim.g.etc_neovim_schemes
if schemes then
  assert(loadfile(vim.g.etc_neovim_dir .. "/tinted-polarity.lua"))()(schemes)
end

local conform = has("conform")
if conform then
  conform.setup({
    format_on_save = {
      timeout_ms = 1000,
      lsp_format = "fallback",
    },
    formatters_by_ft = {
      nix = { "nixfmt" },
    },
  })
end

local blink = has("blink.cmp")
if blink then
  blink.setup({
    keymap = {
      preset = "none",
      ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
      ["<C-e>"] = { "cancel", "fallback" },
      ["<CR>"] = { "accept", "fallback" },
      ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
      ["<Up>"] = { "select_prev", "fallback" },
      ["<Down>"] = { "select_next", "fallback" },
      ["<C-b>"] = { "scroll_documentation_up", "fallback" },
      ["<C-f>"] = { "scroll_documentation_down", "fallback" },
      ["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
    },
    sources = {
      default = { "lsp", "path", "snippets" },
      providers = {
        lsp = { fallbacks = {} },
        path = { fallbacks = {} },
      },
    },
    completion = {
      list = {
        selection = {
          preselect = false,
          auto_insert = false,
        },
      },
    },
    signature = {
      enabled = true,
    },
  })
end

local lsp_capabilities = blink and blink.get_lsp_capabilities() or nil

local function lsp(server, config)
  config = config or {}
  if lsp_capabilities then
    config.capabilities = vim.tbl_deep_extend("force", config.capabilities or {}, lsp_capabilities)
  end
  vim.lsp.config(server, config)
  vim.lsp.enable(server)
end

lsp("bashls")
lsp("lua_ls")
lsp("nixd")
lsp("yamlls", { filetypes = { "yaml" } })
lsp("jsonls")
lsp("ts_ls", {
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
})
lsp("markdown_oxide")
lsp("nushell")
lsp("zls")
lsp("tinymist")
lsp("rust_analyzer")

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local opts = { buffer = args.buf, silent = true }
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
  end,
})

local schemastore = has("schemastore")
if schemastore then
  assert(loadfile(vim.g.etc_neovim_dir .. "/schemastore.lua"))()
end

local treesitter = has("nvim-treesitter.configs")
if treesitter then
  treesitter.setup({
    highlight = { enable = true },
    indent = { enable = true },
  })
end

local gitsigns = has("gitsigns")
if gitsigns then
  gitsigns.setup()
end

local lightbulb = has("nvim-lightbulb")
if lightbulb then
  lightbulb.setup({
    autocmd = { enabled = true },
  })
end

local lualine = has("lualine")
if lualine then
  lualine.setup({
    options = {
      theme = "tinted",
    },
  })
end

local bufferline = has("bufferline")
if bufferline then
  bufferline.setup({
    options = {
      indicator = {
        icon = "▎",
        style = "icon",
      },
      numbers = "none",
      hover = {
        enabled = false,
      },
      tab_size = 14,
    },
  })
  assert(loadfile(vim.g.etc_neovim_dir .. "/tinted-bufferline.lua"))()
  vim.keymap.set("n", "<C-Tab>", "<Cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
  vim.keymap.set("n", "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", { desc = "Prev buffer" })
end

local telescope = has("telescope")
if telescope then
  telescope.setup({
    pickers = {
      find_files = {
        find_command = { "fd", "--type=file" },
      },
    },
    defaults = {
      layout_strategy = "flex",
      vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case",
        "--hidden",
        "--no-ignore",
      },
      file_ignore_patterns = { "node_modules", "%.git/", "dist/", "build/", "target/", "result/" },
      path_display = { "absolute" },
      set_env = { COLORTERM = "truecolor" },
      sorting_strategy = "ascending",
      layout_config = {
        horizontal = {
          prompt_position = "top",
          preview_width = 0.55,
        },
        vertical = {
          mirror = false,
        },
        width = 0.8,
        height = 0.8,
        preview_cutoff = 120,
      },
    },
  })
  pcall(telescope.load_extension, "noice")
  pcall(telescope.load_extension, "notify")

  local builtin = require("telescope.builtin")
  vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files [Telescope]" })
  vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep [Telescope]" })
  vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers [Telescope]" })
  vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags [Telescope]" })
  vim.keymap.set("n", "<leader>ft", "<Cmd>Telescope<CR>", { desc = "Open [Telescope]" })
  vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "Resume (previous search) [Telescope]" })
  vim.keymap.set("n", "<leader>fvf", builtin.git_files, { desc = "Git files [Telescope]" })
  vim.keymap.set("n", "<leader>fvcw", builtin.git_commits, { desc = "Git commits [Telescope]" })
  vim.keymap.set("n", "<leader>fvcb", builtin.git_bcommits, { desc = "Git buffer commits [Telescope]" })
  vim.keymap.set("n", "<leader>fvb", builtin.git_branches, { desc = "Git branches [Telescope]" })
  vim.keymap.set("n", "<leader>fvs", builtin.git_status, { desc = "Git status [Telescope]" })
  vim.keymap.set("n", "<leader>fvx", builtin.git_stash, { desc = "Git stash [Telescope]" })
  vim.keymap.set("n", "<leader>flsb", builtin.lsp_document_symbols, { desc = "LSP Document Symbols [Telescope]" })
  vim.keymap.set("n", "<leader>flsw", builtin.lsp_workspace_symbols, { desc = "LSP Workspace Symbols [Telescope]" })
  vim.keymap.set("n", "<leader>flr", builtin.lsp_references, { desc = "LSP References [Telescope]" })
  vim.keymap.set("n", "<leader>fli", builtin.lsp_implementations, { desc = "LSP Implementations [Telescope]" })
  vim.keymap.set("n", "<leader>flD", builtin.lsp_definitions, { desc = "LSP Definitions [Telescope]" })
  vim.keymap.set("n", "<leader>flt", builtin.lsp_type_definitions, { desc = "LSP Type Definitions [Telescope]" })
  vim.keymap.set("n", "<leader>fld", builtin.diagnostics, { desc = "Diagnostics [Telescope]" })
  vim.keymap.set("n", "<leader>fs", builtin.treesitter, { desc = "Treesitter [Telescope]" })
end

local snacks = has("snacks")
if snacks then
  snacks.setup({
    explorer = { enabled = true },
    picker = {
      enabled = true,
      sources = {
        explorer = {
          hidden = true,
          auto_close = true,
          layout = {
            preset = "sidebar",
            preview = "main",
          },
        },
      },
    },
    image = { enabled = true },
  })
  vim.keymap.set("n", "<leader>tt", function()
    snacks.explorer()
  end, { desc = "Toggle snacks explorer" })
end

local which_key = has("which-key")
if which_key then
  which_key.setup()
end

local ibl = has("ibl")
if ibl then
  ibl.setup()
end

local scrollbar = has("scrollbar")
if scrollbar then
  scrollbar.setup()
end

local illuminate = has("illuminate")
if illuminate then
  illuminate.configure()
end

local noice = has("noice")
if noice then
  noice.setup({
    lsp = {
      signature = {
        enabled = true,
      },
    },
  })
end

local notify = has("notify")
if notify then
  vim.notify = notify
end
