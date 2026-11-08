#!/usr/bin/env bash
# Assembles the download page into build/site (published by .github/workflows/pages.yml).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/site
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R site/. "$OUT/"
# the animated axolotl uses the real sprite strips
mkdir -p "$OUT/assets/sprites"
cp Characters/axolotl/sprites/idle.png "$OUT/assets/sprites/axolotl-idle.png"
cp Characters/axolotl/sprites/juggle.png "$OUT/assets/sprites/axolotl-juggle.png"
# favicon: Axo's first idle frame, scaled up crisp
python3 - "$OUT/assets/favicon.png" <<'PY' 2>/dev/null || cp Characters/axolotl/sprites/idle.png "$OUT/assets/favicon.png"
import sys
from PIL import Image
Image.open("Characters/axolotl/sprites/idle.png").crop((0, 0, 32, 32)).resize((64, 64), Image.NEAREST).save(sys.argv[1])
PY
echo "site ready in $OUT"
