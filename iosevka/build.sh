#!/usr/bin/env bash
# Build IosevkaCustom from private-build-plans.toml, install to ~/Library/Fonts,
# and update ~/.config/ghostty/iosevka.conf.
#
# Usage: iosevka-build              (builds the plan)
#        iosevka-build --reset      (resets ghostty.conf to JetBrainsMono fallback)
set -euo pipefail

PLAN_NAME="IosevkaCustom"
IOSEVKA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/iosevka-build"
GHOSTTY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/iosevka.conf"
FONT_DIR="$HOME/Library/Fonts"

if [[ "${1:-}" == "--reset" ]]; then
  echo "font-family = JetBrainsMono Nerd Font" > "$GHOSTTY_CONF"
  echo "✓ Reset to JetBrainsMono. Press ctrl+shift+, in Ghostty to reload."
  exit 0
fi

if [ ! -d "$IOSEVKA_DIR/.git" ]; then
  echo "✗ Iosevka build environment not found at $IOSEVKA_DIR"
  echo "  Run ~/etc/iosevka/setup.sh first."
  exit 1
fi

echo "→ Syncing build plan..."
cp "$HOME/etc/iosevka/private-build-plans.toml" "$IOSEVKA_DIR/private-build-plans.toml"

echo "→ Building $PLAN_NAME (Regular, Upright only)..."
echo "  This takes ~90 seconds. Grab a coffee. ☕"
cd "$IOSEVKA_DIR"
time nix shell nixpkgs#nodejs_22 nixpkgs#ttfautohint --command \
  npm run build -- "ttf::${PLAN_NAME}"

echo "→ Installing to $FONT_DIR ..."
# Remove old builds of this plan to avoid stale files
rm -f "$FONT_DIR/${PLAN_NAME}"*.ttf
cp "dist/${PLAN_NAME}/TTF/"*.ttf "$FONT_DIR/"
echo "  Installed: $(ls dist/${PLAN_NAME}/TTF/*.ttf | wc -l | tr -d ' ') TTF file(s)"

echo "→ Updating ghostty config..."
# Extract the 'family = "..."' value from the build plan — that's the font name
# Ghostty sees (distinct from the plan ID used in the build command).
FONT_FAMILY=$(awk -F'"' '/^family[[:space:]]*=/{print $2; exit}' \
  "$HOME/etc/iosevka/private-build-plans.toml")
echo "font-family = ${FONT_FAMILY}" > "$GHOSTTY_CONF"
echo "  font-family = ${FONT_FAMILY}"

echo ""
echo "✓ Done! Press ctrl+shift+, in Ghostty to reload the font."
echo ""
echo "  To go back to JetBrainsMono: iosevka-build --reset"
