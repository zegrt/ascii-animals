#!/bin/zsh
# Packages build/ASCII Animals.app into build/ASCII-Animals.dmg: a styled
# drag-to-Applications window (background art, icon slots, volume icon).
# Also build/ASCII-Animals.zip, the copy the app downloads to update itself.
set -euo pipefail
cd "${0:A:h}/.."
APP="build/ASCII Animals.app"
[[ -d "$APP" ]] || Tools/build.sh

# dmgbuild writes the Finder layout directly (no Finder scripting needed).
VENV=.build-tools/venv
# A venv breaks when the checkout moves (its scripts point at the old path).
if ! $VENV/bin/dmgbuild --help > /dev/null 2>&1; then
  rm -rf $VENV
  python3 -m venv $VENV
  $VENV/bin/pip install --quiet "dmgbuild==1.6.5"
fi

# Retina background: combine the 1x and 2x art into one multi-resolution TIFF.
BG=""
if [[ -f Resources/dmg/background.png && -f Resources/dmg/background@2x.png ]]; then
  BG=build/dmg-background.tiff
  tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png -out $BG 2>/dev/null
fi

rm -f build/ASCII-Animals.dmg
$VENV/bin/dmgbuild -s Tools/dmg-settings.py \
  -D app="$APP" -D background="$BG" -D volume_icon=Resources/AppIcon.icns \
  "ASCII Animals" build/ASCII-Animals.dmg > build/dmgbuild.log 2>&1 || { tail -20 build/dmgbuild.log; exit 1; }
echo "built build/ASCII-Animals.dmg ($(du -h build/ASCII-Animals.dmg | cut -f1))"

rm -f build/ASCII-Animals.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" build/ASCII-Animals.zip
echo "built build/ASCII-Animals.zip ($(du -h build/ASCII-Animals.zip | cut -f1))"
