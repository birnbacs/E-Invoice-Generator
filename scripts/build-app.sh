#!/bin/zsh
# Baut "BMW E-Rechnung.app" nach build/ – ohne Xcode-Projekt, direkt aus dem Swift-Paket.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product InvoiceApp
APP="build/BMW E-Rechnung.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/InvoiceApp "$APP/Contents/MacOS/BMW E-Rechnung"
cp Config/config.json "$APP/Contents/Resources/config.json"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BMW E-Rechnung</string>
  <key>CFBundleDisplayName</key><string>BMW E-Rechnung</string>
  <key>CFBundleIdentifier</key><string>de.zweibruecken-ip.bmw-e-invoice</string>
  <key>CFBundleExecutable</key><string>BMW E-Rechnung</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Fertig: $APP"
