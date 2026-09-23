#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --product MacPower
APP="${MACPOWER_APP_OUTPUT:-$PWD/build/MacPower.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR=$(swift build -c release --show-bin-path)
cp "$BIN_DIR/MacPower" "$APP/Contents/MacOS/MacPower"
# Remove debug map paths from the distributable copy; sign the final contents below.
/usr/bin/strip -S "$APP/Contents/MacOS/MacPower"
swift scripts/make-icon.swift "$PWD/build/MacPower.iconset"
/usr/bin/iconutil -c icns "$PWD/build/MacPower.iconset" -o "$APP/Contents/Resources/MacPower.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleExecutable</key><string>MacPower</string>
<key>CFBundleIdentifier</key><string>app.macpower.local</string>
<key>CFBundleName</key><string>MacPower</string>
<key>CFBundleDisplayName</key><string>MacPower</string>
<key>CFBundleIconFile</key><string>MacPower</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict "$APP"
print "Built: $APP"
