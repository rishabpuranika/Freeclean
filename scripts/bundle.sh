#!/bin/bash
# Builds FreeClean.app (universal: Apple Silicon + Intel) and the freeclean CLI in release mode.
#   scripts/bundle.sh            -> build/FreeClean.app, build/freeclean
#   scripts/bundle.sh --install  -> also copies the app to ~/Applications and the CLI to ~/.local/bin
#   scripts/bundle.sh --dmg      -> also packages build/FreeClean-<version>.dmg for sharing
# Options can be combined. Set VERSION=1.2 to stamp a version (default 1.0).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0}"
INSTALL=false
DMG=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --dmg) DMG=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# The app is built universal. The CLI is built for this Mac only: Command Line Tools lack x86_64 copies of
# the Swift compatibility libraries it links. Both builds share one output folder, so copy each binary
# out right after building it.
APP=build/FreeClean.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release --product freeclean
cp "$(swift build -c release --show-bin-path)/freeclean" build/freeclean
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --product FreeCleanApp "${ARCHS[@]}"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/FreeCleanApp" "$APP/Contents/MacOS/FreeClean"
swift scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns" >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FreeClean</string>
  <key>CFBundleDisplayName</key><string>FreeClean</string>
  <key>CFBundleIdentifier</key><string>local.freeclean.app</string>
  <key>CFBundleExecutable</key><string>FreeClean</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
codesign --force -s - build/freeclean
echo "Built $APP and build/freeclean ($(lipo -archs "$APP/Contents/MacOS/FreeClean"))"

if $INSTALL; then
  mkdir -p ~/Applications ~/.local/bin
  rm -rf ~/Applications/FreeClean.app
  cp -R "$APP" ~/Applications/
  cp build/freeclean ~/.local/bin/freeclean
  echo "Installed ~/Applications/FreeClean.app and ~/.local/bin/freeclean"
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || echo "Add ~/.local/bin to your PATH to use 'freeclean' anywhere."
fi

if $DMG; then
  # Drag-to-install disk image with a designed window: branded background, the app and an Applications
  # shortcut placed either side of an arrow, large icons, no toolbar, and the app icon on the volume.
  # Finder stores the layout in the image's .DS_Store, so it's set once here by scripting Finder.
  VOL="FreeClean $VERSION"
  OUT="build/FreeClean-$VERSION.dmg"
  RW=build/FreeClean-rw.dmg
  STAGE=build/dmg
  if [[ -d "/Volumes/$VOL" ]]; then
    echo "A volume named '$VOL' is already mounted; eject it first." >&2; exit 1
  fi
  rm -rf "$STAGE" "$OUT" "$RW"
  mkdir -p "$STAGE/.background"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  swift scripts/make-dmg-background.swift "$STAGE/.background" >/dev/null
  # One HiDPI-aware TIFF holding both resolutions, so the background is sharp on Retina screens.
  tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
    -out "$STAGE/.background/background.tiff" 2>/dev/null
  rm "$STAGE/.background/"background*.png

  hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov -quiet "$RW"
  DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')

  # Window: 660 wide and ~470pt of content (the artwork is 480 tall); everything important sits in the top
  # ~385pt, so it still fits when the viewer's Finder shows a tab bar. Icons go where the artwork expects them.
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    set bounds of container window to {200, 120, 860, 620}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "FreeClean.app" of container window to {170, 215}
    set position of item "Applications" of container window to {490, 215}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

  # The disk's own icon. Added after the Finder step, which removes .VolumeIcon.icns and the custom-icon flag.
  cp "$APP/Contents/Resources/AppIcon.icns" "/Volumes/$VOL/.VolumeIcon.icns"
  SetFile -a C "/Volumes/$VOL"
  rm -rf "/Volumes/$VOL/.fseventsd"
  sync
  # Finder or Spotlight may still be touching the volume for a moment; retry before forcing.
  for _ in 1 2 3 4 5; do hdiutil detach "$DEV" -quiet && break; sleep 2; done
  [[ -e "$DEV" ]] && hdiutil detach "$DEV" -force -quiet || true
  hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -quiet -o "$OUT"
  rm -rf "$STAGE" "$RW"
  echo "Packaged $OUT ($(du -h "$OUT" | cut -f1))"
fi
