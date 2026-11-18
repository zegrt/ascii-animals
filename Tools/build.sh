#!/bin/zsh
# Builds build/ASCII Sharks.app: runs the checks, builds a universal binary,
# assembles and ad-hoc signs the bundle. REGEN_ICON=1 re-renders the icon
# (needs a GPU); otherwise the committed Resources/AppIcon.icns is used.
set -euo pipefail
cd "${0:A:h}/.."

APP="build/ASCII Sharks.app"
mkdir -p build

echo "== checks"
swift run -c release OceanChecks > build/checks.log 2>&1 || { tail -20 build/checks.log; echo "checks failed"; exit 1; }
tail -1 build/checks.log

echo "== build (arm64, x86_64)"
bins=()
for arch in arm64 x86_64; do
  swift build -c release --arch $arch --scratch-path .build-$arch --product ASCIISharks > build/build-$arch.log 2>&1 \
    || { tail -20 build/build-$arch.log; exit 1; }
  # The output layout differs between toolchains; ask SwiftPM where it is.
  bins+=("$(swift build -c release --arch $arch --scratch-path .build-$arch --show-bin-path)/ASCIISharks")
done

if [[ "${REGEN_ICON:-0}" == 1 ]]; then
  echo "== icon"
  rm -rf build/AppIcon.iconset
  swift run -c release OceanTool iconset build/AppIcon.iconset > /dev/null
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "== bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/ASCIISharks"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/GeistMono.ttf "$APP/Contents/Resources/GeistMono.ttf"   # UI text (welcome, About)
cp Resources/OFL.txt "$APP/Contents/Resources/GeistMono-OFL.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

codesign --force --sign - --identifier local.ascii-sharks.wallpaper "$APP"
codesign --verify --strict "$APP"
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/ASCIISharks"))"
