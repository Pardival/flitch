#!/usr/bin/env bash
# Builds a release Flitch.app (ad-hoc signed) and packs it in a DMG.
#   scripts/build-dmg.sh 0.2.0          → build/release/Flitch-0.2.0.dmg (+ .sha256)
# Env: SPARKLE_PUBLIC_KEY (optional, enables updates), BUILD_NUMBER (default: commit count).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: build-dmg.sh <version>}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
OUT=build/release
rm -rf "$OUT"
mkdir -p "$OUT"

command -v xcodegen >/dev/null || { echo "xcodegen is required (brew install xcodegen)"; exit 1; }
xcodegen generate --quiet

xcodebuild -project Flitch.xcodeproj -scheme Flitch -configuration Release \
  -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}" \
  CODE_SIGN_IDENTITY="-" build | tail -3

APP=build/DerivedData/Build/Products/Release/Flitch.app
# ad-hoc signature, inside out (Sparkle's helpers first), keeping the entitlements
codesign --force --deep --options runtime --sign - \
  --entitlements App/Flitch.entitlements "$APP"
codesign --verify --deep --strict "$APP"

DMG="$OUT/Flitch-$VERSION.dmg"
if command -v create-dmg >/dev/null; then
  # 1x + 2x in one TIFF for Retina screens
  tiffutil -cathidpicheck art/dmg/background.png art/dmg/background@2x.png -out "$OUT/background.tiff"
  create-dmg --volname "Flitch" --background "$OUT/background.tiff" \
    --window-size 660 400 --icon-size 112 --icon "Flitch.app" 170 190 \
    --app-drop-link 490 190 --hide-extension "Flitch.app" --no-internet-enable \
    "$DMG" "$APP"
else
  echo "create-dmg not found: plain DMG (brew install create-dmg for the styled window)"
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname Flitch -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
fi

shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
echo "$DMG"
echo "sha256 $(cat "$DMG.sha256")"
