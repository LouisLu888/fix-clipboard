#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Fix Clipboard.app"
mkdir -p "$ROOT/build"
mkdir -p "$APP/Contents/MacOS"
for ARCH in arm64 x86_64; do
  xcrun swiftc "$ROOT/source/main.swift" -target "${ARCH}-apple-macos13.0" -o "$ROOT/build/FixClipboard-$ARCH" -framework AppKit -framework Network -module-cache-path "${TMPDIR:-/tmp}/fix_clipboard_swift_cache"
done
xcrun lipo -create "$ROOT/build/FixClipboard-arm64" "$ROOT/build/FixClipboard-x86_64" -output "$APP/Contents/MacOS/FixClipboard"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FixClipboard</string>
<key>CFBundleIdentifier</key><string>local.louis.fixclipboard</string>
<key>CFBundleName</key><string>Fix Clipboard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/FixClipboard" --self-test

codesign --verify --strict "$APP"
cp "$ROOT/INSTALL.md" "$ROOT/dist/INSTALL.md"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ROOT/dist/Fix-Clipboard-1.2.1-universal.zip"
(cd "$ROOT/dist" && shasum -a 256 Fix-Clipboard-1.2.1-universal.zip > SHA256SUMS.txt)
