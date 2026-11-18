#!/bin/zsh
# Removes ASCII Sharks completely: puts your wallpaper back, then removes the
# login item, settings, saved stills, logs and the app.
set -euo pipefail
for app in "$HOME/Applications/ASCII Sharks.app" "/Applications/ASCII Sharks.app"; do
  if [[ -d "$app" ]]; then
    "$app/Contents/MacOS/ASCIISharks" --uninstall --yes
    exit 0
  fi
done
echo "ASCII Sharks isn't in ~/Applications or /Applications."
exit 1
