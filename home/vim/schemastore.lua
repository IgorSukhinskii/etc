local schemastore = require("schemastore")
local json_settings = {
  json = {
    schemas = schemastore.json.schemas({
      select = { "package.json", "tsconfig.json", "Expo SDK" },
    }),
    validate = { enable = true },
  },
}
local yaml_settings = {
  yaml = {
    schemaStore = {
      enable = true,
      url = "https://www.schemastore.org/api/json/catalog.json",
    },
  },
}
vim.lsp.config("jsonls", { settings = json_settings })
vim.lsp.config("yaml-language-server", { settings = yaml_settings })
