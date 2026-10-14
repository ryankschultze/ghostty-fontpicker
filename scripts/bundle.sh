#!/bin/sh
# Wraps the built executable in a minimal app bundle: build/FontPicker.app.
#
#   scripts/bundle.sh .build/release/fontpicker
set -eu

binary=${1:?usage: scripts/bundle.sh <path to built fontpicker>}
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/build/FontPicker.app"
version=$("$binary" version)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/fontpicker"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>fontpicker</string>
    <key>CFBundleIdentifier</key>
    <string>local.fontpicker</string>
    <key>CFBundleName</key>
    <string>Font Picker</string>
    <key>CFBundleDisplayName</key>
    <string>Ghostty Font Picker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
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
PLIST

# Ad-hoc signature, so macOS treats the bundle as one consistent app on this machine.
codesign --force --sign - "$app" >/dev/null 2>&1 || echo "note: codesign failed; the app still runs unsigned" >&2
echo "Built $app"
