#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/DevRunner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/DevRunner" "$APP/Contents/MacOS/DevRunner"
chmod +x "$APP/Contents/MacOS/DevRunner"
if compgen -G ".build/release/*.bundle" > /dev/null; then
  cp -R .build/release/*.bundle "$APP/Contents/MacOS/"
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
echo "Created $APP"
