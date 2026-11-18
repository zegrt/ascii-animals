#!/bin/zsh
# Builds build/ASCII Sharks.app: runs the checks, builds a universal binary,
# renders the icon, assembles and ad-hoc signs the bundle.
set -euo pipefail
cd "${0:A:h}/.."

APP="build/ASCII Sharks.app"
mkdir -p build

echo "== checks"
swift run -c release OceanChecks > build/checks.log 2>&1 || { tail -20 build/checks.log; echo "checks failed"; exit 1; }
tail -1 build/checks.log

echo "== build (arm64, x86_64)"
for arch in arm64 x86_64; do
  swift build -c release --arch $arch --scratch-path .build-$arch --product ASCIISharks > build/build-$arch.log 2>&1 \
    || { tail -20 build/build-$arch.log; exit 1; }
done

echo "== icon"
rm -rf build/AppIcon.iconset build/AppIcon.icns
swift run -c release OceanTool iconset build/AppIcon.iconset > /dev/null
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "== bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  .build-arm64/out/Products/Release/ASCIISharks \
  .build-x86_64/out/Products/Release/ASCIISharks \
  -output "$APP/Contents/MacOS/ASCIISharks"
cp Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/OFL.txt "$APP/Contents/Resources/GeistMono-OFL.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

codesign --force --sign - --identifier local.ascii-sharks.wallpaper "$APP"
codesign --verify --strict "$APP"
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/ASCIISharks"))"
