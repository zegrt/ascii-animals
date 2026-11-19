#!/bin/zsh
# Installs build/ASCII Animals.app into ~/Applications and launches it.
# Quitting the running copy first lets it put the original wallpaper back.
set -euo pipefail
cd "${0:A:h}/.."
SRC="build/ASCII Animals.app"
DST="$HOME/Applications/ASCII Animals.app"
[[ -d "$SRC" ]] || { echo "run Tools/build.sh first"; exit 1; }

if pgrep -x ASCIIAnimals > /dev/null; then
  pkill -TERM -x ASCIIAnimals
  for _ in {1..50}; do pgrep -x ASCIIAnimals > /dev/null || break; sleep 0.1; done
fi
mkdir -p "$HOME/Applications"
rm -rf "$DST"
cp -R "$SRC" "$DST"
open "$DST"
echo "installed and launched $DST"
