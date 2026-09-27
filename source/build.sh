#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Fix Clipboard.app"
mkdir -p "$ROOT/build"
mkdir -p "$APP/Contents/MacOS"
for ARCH in arm64 x86_64; do
  xcrun swiftc "$ROOT/source/main.swift" "$ROOT/source/DiagnosticsUI.swift" "$ROOT/source/Licensing.swift" "$ROOT/source/ProUI.swift" "$ROOT/source/LicenseTests.swift" -target "${ARCH}-apple-macos13.0" -o "$ROOT/build/FixClipboard-$ARCH" -framework AppKit -framework Network -framework CoreWLAN -framework IOBluetooth -framework CoreBluetooth -framework Security -framework ServiceManagement -module-cache-path "${TMPDIR:-/tmp}/fix_clipboard_swift_cache"
done
xcrun lipo -create "$ROOT/build/FixClipboard-arm64" "$ROOT/build/FixClipboard-x86_64" -output "$APP/Contents/MacOS/FixClipboard"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FixClipboard</string>
<key>CFBundleIdentifier</key><string>local.louis.fixclipboard</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Fix Clipboard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.5.0</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>用于诊断蓝牙电源状态，帮助排查通用剪贴板问题；不会扫描或连接附近设备。</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/config/Commerce.json" "$APP/Contents/Resources/Commerce.json"
xcrun swift -module-cache-path "${TMPDIR:-/tmp}/fix_clipboard_swift_cache" "$ROOT/source/make-icon.swift" "$ROOT/build/AppIcon.iconset"
xcrun iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/FixClipboard" --self-test

codesign --verify --strict "$APP"
cp "$ROOT/INSTALL.md" "$ROOT/dist/INSTALL.md"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ROOT/dist/Fix-Clipboard-1.5.0-beta.1-universal.zip"
(cd "$ROOT/dist" && shasum -a 256 Fix-Clipboard-1.5.0-beta.1-universal.zip > SHA256SUMS.txt)
