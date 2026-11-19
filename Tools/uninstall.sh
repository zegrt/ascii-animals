#!/bin/zsh
# Removes ASCII Animals completely: puts your wallpaper back, then removes the
# login item, settings, saved stills, logs and the app.
set -euo pipefail
for app in "$HOME/Applications/ASCII Animals.app" "/Applications/ASCII Animals.app"; do
  if [[ -d "$app" ]]; then
    "$app/Contents/MacOS/ASCIIAnimals" --uninstall --yes
    exit 0
  fi
done
echo "ASCII Animals isn't in ~/Applications or /Applications."
exit 1
