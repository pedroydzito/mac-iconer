#!/bin/sh
# Compila o Renicon e monta o pacote Renicon.app em ./build
set -e
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --show-bin-path)/Renicon"

APP="build/Renicon.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Renicon"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --deep -s - "$APP"
echo "Pronto: $APP"
echo "Para instalar: mv \"$APP\" /Applications/"
