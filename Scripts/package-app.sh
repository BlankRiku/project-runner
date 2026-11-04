#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$(xcrun --show-sdk-path --sdk macosx)"
swift build -c release --triple arm64-apple-macosx13.0 --sdk "$sdk"
cp ".build/release/DevRunner" "/tmp/DevRunner-arm64"
swift build -c release --triple x86_64-apple-macosx13.0 --sdk "$sdk"
cp ".build/release/DevRunner" "/tmp/DevRunner-x86_64"
APP="dist/DevRunner.app"
DMG="dist/DevRunner.dmg"
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "/tmp/DevRunner-arm64" "/tmp/DevRunner-x86_64" -output "$APP/Contents/MacOS/DevRunner"
chmod +x "$APP/Contents/MacOS/DevRunner"
rm -f "/tmp/DevRunner-arm64" "/tmp/DevRunner-x86_64"
bundles=(.build/release/*.bundle(N))
if (( $#bundles )); then
  cp -R "${bundles[@]}" "$APP/Contents/Resources/"
fi
icon_src="Sources/DevRunner/Resources/AppIcon.png"
if [[ -f "$icon_src" ]]; then
  workdir=$(mktemp -d)
  iconset="$workdir/AppIcon.iconset"
  mkdir -p "$iconset"
  sips -z 16 16 "$icon_src" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32 "$icon_src" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$icon_src" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64 "$icon_src" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$icon_src" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256 "$icon_src" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$icon_src" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512 "$icon_src" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$icon_src" --out "$iconset/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$icon_src" --out "$iconset/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$workdir"
fi
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>it</string>
  <key>CFBundleExecutable</key>
  <string>DevRunner</string>
  <key>CFBundleIdentifier</key>
  <string>it.icsone.dev-runner</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Dev Runner</string>
  <key>CFBundleDisplayName</key>
  <string>Dev Runner</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)
if [[ -z "$identity" ]]; then
  echo "Developer ID Application non trovato nel portachiavi." >&2
  exit 1
fi
while IFS= read -r nested; do
  codesign --force --sign "$identity" --options runtime --timestamp "$nested"
done < <(find "$APP/Contents" -type d \( -name "*.bundle" -o -name "*.framework" \) | sort)
codesign --force --sign "$identity" --options runtime --timestamp "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
stage="$(mktemp -d)"
cp -R "$APP" "$stage/Dev Runner.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Dev Runner" -srcfolder "$stage" -ov -format UDZO "$DMG"
rm -rf "$stage"
codesign --force --sign "$identity" --timestamp "$DMG"
echo "Created $APP"
echo "Created $DMG"
lipo -info "$APP/Contents/MacOS/DevRunner"
echo "Signed with $identity"
