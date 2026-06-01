#!/usr/bin/env bash
# One-time setup: clone Iosevka source and install npm deps.
# Run this once before using build.sh.
set -euo pipefail

IOSEVKA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/iosevka-build"

echo "→ Setting up Iosevka build environment at $IOSEVKA_DIR"

if [ ! -d "$IOSEVKA_DIR/.git" ]; then
  echo "  Cloning Iosevka (shallow)..."
  git clone --depth 1 https://github.com/be5invis/Iosevka "$IOSEVKA_DIR"
else
  echo "  Iosevka already cloned. Pulling latest..."
  git -C "$IOSEVKA_DIR" pull --ff-only
fi

echo "  Installing npm dependencies (via nix shell nodejs_22)..."
cd "$IOSEVKA_DIR"
nix shell nixpkgs#nodejs_22 --command npm install

echo ""
echo "✓ Setup complete!"
echo "  Edit ~/etc/iosevka/private-build-plans.toml, then run:"
echo "    iosevka-build"
