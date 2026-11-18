#!/bin/zsh
# Packages build/ASCII Sharks.app into build/ASCII-Sharks.dmg (drag-to-Applications).
set -euo pipefail
cd "${0:A:h}/.."
APP="build/ASCII Sharks.app"
[[ -d "$APP" ]] || Tools/build.sh
STAGE=build/dmg
rm -rf "$STAGE" build/ASCII-Sharks.dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First time? Read me.txt" <<'TXT'
ASCII Sharks — live wallpaper

1. Drag "ASCII Sharks" onto the Applications folder.
2. Open it from Applications. macOS will say it can't verify the app
   (it isn't from the App Store or a registered developer).
3. Open System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to ASCII Sharks. Confirm once. That's it.

   Or, in Terminal:
   xattr -dr com.apple.quarantine "/Applications/ASCII Sharks.app"

The ocean appears behind your desktop icons. Find the fish icon in the
menu bar for settings, pause and quit. Quitting puts your own wallpaper back.

Needs macOS 14 or later. Source and credits:
https://github.com/zegrt/ascii-sharks-wallpaper
TXT
hdiutil create -quiet -volname "ASCII Sharks" -srcfolder "$STAGE" -ov -format UDZO build/ASCII-Sharks.dmg
rm -rf "$STAGE"
echo "built build/ASCII-Sharks.dmg ($(du -h build/ASCII-Sharks.dmg | cut -f1))"
