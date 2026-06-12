#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
OUTPUT_DIR=${1:-"$ROOT_DIR/dist"}
APP_NAME="Cast-a-mac Host"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift Scripts/generate-app-icons.swift
iconutil -c icns "Assets/CastAMac.iconset" -o "Assets/CastAMac.icns"
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer} \
    swift build -c release --product cast-host-app

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/cast-host-app" "$MACOS_DIR/Cast-a-mac Host"
cp "Assets/CastAMac.icns" "$RESOURCES_DIR/CastAMac.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Cast-a-mac Host</string>
    <key>CFBundleIdentifier</key>
    <string>com.castamac.host</string>
    <key>CFBundleIconFile</key>
    <string>CastAMac</string>
    <key>CFBundleName</key>
    <string>Cast-a-mac Host</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Cast-a-mac streams this Mac display to your paired iPad.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
