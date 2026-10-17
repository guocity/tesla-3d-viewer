#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/TeslaMetalViewer.app"
BIN_DIR="$SCRIPT_DIR/.build/out/Products/Release"

if [ ! -f "$BIN_DIR/TeslaMetalViewer" ]; then
    echo "Release binary not found, building with swift build -c release..."
    swift build -c release
fi

echo "Creating TeslaMetalViewer.app macOS bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/TeslaMetalViewer" "$APP_DIR/Contents/MacOS/TeslaMetalViewer"
chmod +x "$APP_DIR/Contents/MacOS/TeslaMetalViewer"

# Copy models folder directly into Resources so the app bundle is completely
# self-contained and never triggers macOS TCC privacy prompts for Documents
rm -rf "$APP_DIR/Contents/Resources/models"
if [ -d "$SCRIPT_DIR/../models" ]; then
    cp -R "$SCRIPT_DIR/../models" "$APP_DIR/Contents/Resources/models"
elif [ -d "$SCRIPT_DIR/models" ]; then
    cp -R "$SCRIPT_DIR/models" "$APP_DIR/Contents/Resources/models"
fi

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TeslaMetalViewer</string>
    <key>CFBundleIdentifier</key>
    <string>com.tesla.metalviewer</string>
    <key>CFBundleName</key>
    <string>Tesla Metal Studio</string>
    <key>CFBundleDisplayName</key>
    <string>Tesla Metal Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "TeslaMetalViewer.app successfully created at $APP_DIR"
