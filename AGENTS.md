# Nix config verification

Before proposing nix-darwin, home-manager, or app-level config options,
verify against actual source in the nix store first using the followin commands:

## Nix module options (home-manager / nix-darwin)

```bash
nix-hm-module <name>        # prints full source of modules/programs/<name>.nix
nix-darwin-module <name>    # prints paths of nix-darwin modules matching <name>
```

If the HM module is a YAML/TOML passthrough (type = yamlFormat, no option
definitions), the app's own config struct is the source of truth -> use
nix-src-search.

## App-level config schema (YAML/TOML passed through by HM)

```bash
nix-src-search <pkg> <file-glob> <grep-pattern>
# e.g. nix-src-search lazygit "*.go" "Pagers|Paging"
# e.g. nix-src-search starship "*.rs" "Config|config_str"
```

Output: file paths + grep preview. Use Read tool on the relevant file for full
content. Works for uninstalled packages.

## Rebuild

```bash
nix-rebuild    # rebuilds for current hostname
```
