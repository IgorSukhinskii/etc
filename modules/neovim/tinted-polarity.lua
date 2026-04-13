local tinted = require("tinted-nvim")

tinted.setup({
  apply_scheme_on_startup = false,
  ui = {
    transparent = true,
  },
  schemes = {
    ["base24-dark"] = __DARK_SCHEME__,
    ["base24-light"] = __LIGHT_SCHEME__,
  },
})

-- DEC mode 2031 sets vim.o.background directly; keep scheme in sync.
-- Guard against re-entrancy: tinted.load() sets background, which fires OptionSet again.
local function apply_scheme()
  local scheme = (vim.o.background == "dark") and "base24-dark" or "base24-light"
  if tinted.get_scheme() ~= scheme then
    tinted.load(scheme)
  end
end

vim.api.nvim_create_autocmd("OptionSet", {
  pattern = "background",
  callback = apply_scheme,
})

-- Initial call fixes black icon background on first open.
apply_scheme()
