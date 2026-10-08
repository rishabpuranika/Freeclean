#!/bin/bash
# Builds FreeClean.app and the freeclean CLI in release mode.
#   scripts/bundle.sh            -> build/FreeClean.app, build/freeclean
#   scripts/bundle.sh --install  -> also copies the app to ~/Applications and the CLI to ~/.local/bin
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product FreeCleanApp
swift build -c release --product freeclean
BIN=$(swift build -c release --show-bin-path)

APP=build/FreeClean.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FreeCleanApp" "$APP/Contents/MacOS/FreeClean"
cp "$BIN/freeclean" build/freeclean

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FreeClean</string>
  <key>CFBundleDisplayName</key><string>FreeClean</string>
  <key>CFBundleIdentifier</key><string>local.freeclean.app</string>
  <key>CFBundleExecutable</key><string>FreeClean</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Built $APP and build/freeclean"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications ~/.local/bin
  rm -rf ~/Applications/FreeClean.app
  cp -R "$APP" ~/Applications/
  cp build/freeclean ~/.local/bin/freeclean
  echo "Installed ~/Applications/FreeClean.app and ~/.local/bin/freeclean"
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || echo "Add ~/.local/bin to your PATH to use 'freeclean' anywhere."
fi
