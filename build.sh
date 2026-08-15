#!/bin/zsh
# Builds Writer.app — a forward-only writing app.
#   ./build.sh            build into build/Writer.app
#   ./build.sh install    build, then copy to /Applications
set -e
cd "$(dirname "$0")"

APP=build/Writer.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc Sources/Writer/main.swift \
    -O \
    -o "$APP/Contents/MacOS/Writer" \
    -framework AppKit

cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Writer</string>
    <key>CFBundleDisplayName</key>
    <string>Writer</string>
    <key>CFBundleIdentifier</key>
    <string>dev.neall.writer</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Writer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Writer uses the microphone for dictation.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Writer uses speech recognition for dictation.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "$1" == "install" ]]; then
    rm -rf /Applications/Writer.app
    cp -R "$APP" /Applications/Writer.app
    echo "Installed to /Applications/Writer.app"
fi
