require("telescope").setup({
  defaults = {
    layout_strategy = "flex",
    layout_config = {
      flip_columns = 120,
      flip_lines = 40,
      horizontal = { preview_cutoff = 0 },
      vertical = { preview_cutoff = 0 },
    },
  },
})
