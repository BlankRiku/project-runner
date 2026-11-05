#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist-signed/DevRunner.app"
DMG="dist-signed/DevRunner.dmg"
rm -f "$DMG"
mkdir -p dist-signed
Scripts/assemble-app.sh "$APP"
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
