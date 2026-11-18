#!/bin/zsh
# Builds build/ASCII Sharks.app: bundles the web ocean, compiles the app, signs it ad hoc.
set -euo pipefail
cd "${0:A:h}"

ESBUILD=../ascii-sharks/node_modules/.bin/esbuild
APP="build/ASCII Sharks.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

"$ESBUILD" web/main.ts --bundle --format=iife --target=safari16 --minify \
  --log-level=warning --outfile="$APP/Contents/Resources/web/app.js"
cp web/index.html web/GeistMono.ttf web/OFL.txt "$APP/Contents/Resources/web/"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -target arm64-apple-macos13 \
  -o "$APP/Contents/MacOS/ASCIISharks" Sources/main.swift

codesign --force --sign - "$APP"
echo "built $APP"
