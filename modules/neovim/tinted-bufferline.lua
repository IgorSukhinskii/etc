local tinted = require("tinted-nvim")

local function apply_bufferline_hl()
  local p = tinted.get_palette()
  if not p then
    return
  end

  local hl = vim.api.nvim_set_hl

  local fill_bg = "NONE"
  local inactive_bg = "NONE"
  local active_bg = "NONE"

  -- TabLineFill is the Neovim tabline window background. Transparent BufferLine groups
  -- fall back to this if it's not cleared, so it must be NONE too.
  hl(0, "TabLineFill", { bg = "NONE" })

  -- Fill area (bar behind all tabs)
  hl(0, "BufferLineFill", { fg = p.base03, bg = fill_bg })

  -- Inactive / background tabs
  hl(0, "BufferLineBackground", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineBufferVisible", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineCloseButton", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineCloseButtonVisible", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineModified", { fg = p.base09, bg = inactive_bg })
  hl(0, "BufferLineModifiedVisible", { fg = p.base09, bg = inactive_bg })
  hl(0, "BufferLineDuplicate", { fg = p.base03, bg = inactive_bg, italic = true })
  hl(0, "BufferLineDuplicateVisible", { fg = p.base03, bg = inactive_bg, italic = true })

  -- Diagnostics (inactive background state)
  hl(0, "BufferLineDiagnostic", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineError", { fg = p.base08, bg = inactive_bg })
  hl(0, "BufferLineErrorDiagnostic", { fg = p.base08, bg = inactive_bg })
  hl(0, "BufferLineWarning", { fg = p.base09, bg = inactive_bg })
  hl(0, "BufferLineWarningDiagnostic", { fg = p.base09, bg = inactive_bg })
  hl(0, "BufferLineInfo", { fg = p.base0D, bg = inactive_bg })
  hl(0, "BufferLineInfoDiagnostic", { fg = p.base0D, bg = inactive_bg })
  hl(0, "BufferLineHint", { fg = p.base0C, bg = inactive_bg })
  hl(0, "BufferLineHintDiagnostic", { fg = p.base0C, bg = inactive_bg })
  hl(0, "BufferLinePick", { fg = p.base08, bg = inactive_bg, bold = true })

  -- Diagnostics (visible in split, not focused) must match inactive bg or icons go wrong.
  hl(0, "BufferLineDiagnosticVisible", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineErrorVisible", { fg = p.base08, bg = inactive_bg })
  hl(0, "BufferLineErrorDiagnosticVisible", { fg = p.base08, bg = inactive_bg })
  hl(0, "BufferLineWarningVisible", { fg = p.base09, bg = inactive_bg })
  hl(0, "BufferLineWarningDiagnosticVisible", { fg = p.base09, bg = inactive_bg })
  hl(0, "BufferLineInfoVisible", { fg = p.base0D, bg = inactive_bg })
  hl(0, "BufferLineInfoDiagnosticVisible", { fg = p.base0D, bg = inactive_bg })
  hl(0, "BufferLineHintVisible", { fg = p.base0C, bg = inactive_bg })
  hl(0, "BufferLineHintDiagnosticVisible", { fg = p.base0C, bg = inactive_bg })
  hl(0, "BufferLinePickVisible", { fg = p.base08, bg = inactive_bg, bold = true })

  -- Thin separators: "thin" style is not state-aware, all use BufferLineSeparator.
  hl(0, "BufferLineSeparator", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineSeparatorVisible", { fg = p.base04, bg = inactive_bg })

  -- Tab bar (vim tabs, not buffer tabs)
  hl(0, "BufferLineTab", { fg = p.base04, bg = inactive_bg })
  hl(0, "BufferLineTabSeparator", { fg = p.base03, bg = inactive_bg })
  hl(0, "BufferLineTabClose", { fg = p.base08, bg = inactive_bg })
  hl(0, "BufferLineOffsetSeparator", { fg = p.base02, bg = fill_bg })

  -- Active / selected tab (matches editor bg)
  hl(0, "BufferLineBufferSelected", { fg = p.base05, bg = active_bg, bold = true })
  hl(0, "BufferLineCloseButtonSelected", { fg = p.base08, bg = active_bg })
  hl(0, "BufferLineModifiedSelected", { fg = p.base09, bg = active_bg })
  hl(0, "BufferLineDuplicateSelected", { fg = p.base04, bg = active_bg, italic = true })
  hl(0, "BufferLineIndicatorVisible", { fg = p.base03, bg = inactive_bg })
  hl(0, "BufferLineIndicatorSelected", { fg = p.base0D, bg = active_bg })

  -- Diagnostics (selected): keep name bold regardless of diagnostic state.
  hl(0, "BufferLineDiagnosticSelected", { fg = p.base04, bg = active_bg, bold = true })
  hl(0, "BufferLineErrorSelected", { fg = p.base08, bg = active_bg, bold = true })
  hl(0, "BufferLineErrorDiagnosticSelected", { fg = p.base08, bg = active_bg, bold = true })
  hl(0, "BufferLineWarningSelected", { fg = p.base09, bg = active_bg, bold = true })
  hl(0, "BufferLineWarningDiagnosticSelected", { fg = p.base09, bg = active_bg, bold = true })
  hl(0, "BufferLineInfoSelected", { fg = p.base0D, bg = active_bg, bold = true })
  hl(0, "BufferLineInfoDiagnosticSelected", { fg = p.base0D, bg = active_bg, bold = true })
  hl(0, "BufferLineHintSelected", { fg = p.base0C, bg = active_bg, bold = true })
  hl(0, "BufferLineHintDiagnosticSelected", { fg = p.base0C, bg = active_bg, bold = true })
  hl(0, "BufferLinePickSelected", { fg = p.base08, bg = active_bg, bold = true })

  -- Active separators highlighted with accent color.
  hl(0, "BufferLineSeparatorSelected", { fg = p.base0D, bg = active_bg })
  hl(0, "BufferLineTabSelected", { fg = p.base05, bg = active_bg })
  hl(0, "BufferLineTabSeparatorSelected", { fg = p.base0D, bg = active_bg })

  -- Reset icon cache so icons re-derive against the transparent background.
  require("bufferline.highlights").reset_icon_hl_cache()
end

apply_bufferline_hl()

-- vim.schedule defers our handler to run after all synchronous autocmds,
-- including bufferline's own handler, so our patches win.
vim.api.nvim_create_autocmd({ "ColorScheme" }, {
  callback = function()
    vim.schedule(apply_bufferline_hl)
  end,
})
