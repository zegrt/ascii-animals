#!/bin/zsh
# Builds build/ASCII Animals.app: runs the checks, builds a universal binary,
# assembles and ad-hoc signs the bundle. REGEN_ICON=1 re-renders the icon
# (needs a GPU); otherwise the committed Resources/AppIcon.icns is used.
#   Tools/build.sh --test   builds the energy-test copy instead (Tools/energy.sh drives it):
#   build/ASCII Animals Test.app, its own bundle ID, name and executable (AppIdentity in OceanKit decides
#   what it may do from that ID: no updater, Sharks hand-over, uninstaller, system wallpaper or login item).
set -euo pipefail
cd "${0:A:h}/.."

REAL_ID="local.ascii-animals.wallpaper"
TEST_ID="local.ascii-animals.energy-test"
TEST_EXE="ASCIIAnimalsEnergyTest"
TEST_NAME="ASCII Animals Test"
if [[ "${1:-}" == --test ]]; then
  APP="build/$TEST_NAME.app"; ID="$TEST_ID"; EXE="$TEST_EXE"
elif [[ $# -eq 0 ]]; then
  APP="build/ASCII Animals.app"; ID="$REAL_ID"; EXE="ASCIIAnimals"
else
  echo "usage: $0 [--test]" >&2; exit 2
fi
mkdir -p build

echo "== checks"
swift run -c release OceanChecks > build/checks.log 2>&1 || { tail -20 build/checks.log; echo "checks failed"; exit 1; }
tail -1 build/checks.log

echo "== build (arm64, x86_64)"
bins=()
for arch in arm64 x86_64; do
  swift build -c release --arch $arch --scratch-path .build-$arch --product ASCIIAnimals > build/build-$arch.log 2>&1 \
    || { tail -20 build/build-$arch.log; exit 1; }
  # The output layout differs between toolchains; ask SwiftPM where it is.
  bins+=("$(swift build -c release --arch $arch --scratch-path .build-$arch --show-bin-path)/ASCIIAnimals")
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
lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/$EXE"
cp Info.plist "$APP/Contents/Info.plist"
if [[ "$ID" == "$TEST_ID" ]]; then
  plist="$APP/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "$TEST_ID" "$plist"
  plutil -replace CFBundleExecutable -string "$TEST_EXE" "$plist"
  plutil -replace CFBundleName -string "$TEST_NAME" "$plist"
  plutil -replace CFBundleDisplayName -string "$TEST_NAME" "$plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/GeistMono.ttf "$APP/Contents/Resources/GeistMono.ttf"   # UI text (welcome, About)
cp Resources/OFL.txt "$APP/Contents/Resources/GeistMono-OFL.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

codesign --force --sign - --identifier "$ID" "$APP"
codesign --verify --strict "$APP"
got="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")"
[[ "$got" == "$ID" && "$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")" == "$EXE" ]] \
  || { echo "the bundle's identity is wrong: $got"; exit 1; }
echo "built $APP: $ID, $EXE ($(lipo -archs "$APP/Contents/MacOS/$EXE")), from $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- Sources Package.swift Info.plist || echo ' + uncommitted changes')"
