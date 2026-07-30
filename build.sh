#!/bin/zsh
# Builds CopyPal.app from main.swift. No Xcode project needed.
set -e
cd "$(dirname "$0")"

swiftc -O main.swift SemanticClassifier.swift -o CopyPal

APP=CopyPal.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv CopyPal "$APP/Contents/MacOS/CopyPal"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CopyPal</string>
    <key>CFBundleIdentifier</key>
    <string>com.ivankaliaev.copypal</string>
    <key>CFBundleName</key>
    <string>CopyPal</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP — launch with: open $APP"
