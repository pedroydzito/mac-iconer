#!/bin/sh
# Compila o Renicon e monta Renicon.app (e Renicon.zip / Renicon.dmg) em ./build
# Uso: ./build.sh [versão]   ex.: ./build.sh 1.2.0
set -e
cd "$(dirname "$0")"
VERSION="${1:-1.0.0}"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Renicon"

APP="build/Renicon.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Renicon"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$(date +%Y%m%d%H%M)/g" Resources/Info.plist > "$APP/Contents/Info.plist"

# Ícone do app
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --deep -s - "$APP"

# Pacotes para distribuição
ditto -c -k --keepParent "$APP" build/Renicon.zip
DMG_DIR="build/dmg"
mkdir -p "$DMG_DIR"
cp -R "$APP" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "Renicon" -srcfolder "$DMG_DIR" -ov -format UDZO build/Renicon.dmg >/dev/null
rm -rf "$DMG_DIR"

echo "Pronto: $APP (versão $VERSION), build/Renicon.zip e build/Renicon.dmg"
