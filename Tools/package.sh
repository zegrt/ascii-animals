#!/bin/zsh
# Packages build/ASCII Sharks.app into build/ASCII-Sharks.dmg: a styled
# drag-to-Applications window (background art, icon slots, volume icon).
set -euo pipefail
cd "${0:A:h}/.."
APP="build/ASCII Sharks.app"
[[ -d "$APP" ]] || Tools/build.sh

# dmgbuild writes the Finder layout directly (no Finder scripting needed).
VENV=.build-tools/venv
if [[ ! -x $VENV/bin/dmgbuild ]]; then
  python3 -m venv $VENV
  $VENV/bin/pip install --quiet "dmgbuild==1.6.5"
fi

# Retina background: combine the 1x and 2x art into one multi-resolution TIFF.
BG=""
if [[ -f Resources/dmg/background.png && -f Resources/dmg/background@2x.png ]]; then
  BG=build/dmg-background.tiff
  tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png -out $BG 2>/dev/null
fi

rm -f build/ASCII-Sharks.dmg
$VENV/bin/dmgbuild -s Tools/dmg-settings.py \
  -D app="$APP" -D background="$BG" -D volume_icon=Resources/AppIcon.icns \
  "ASCII Sharks" build/ASCII-Sharks.dmg > build/dmgbuild.log 2>&1 || { tail -20 build/dmgbuild.log; exit 1; }
echo "built build/ASCII-Sharks.dmg ($(du -h build/ASCII-Sharks.dmg | cut -f1))"
