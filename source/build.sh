#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---candidate}"
VERSION="1.5.0"
BUILD="12"
if [[ "$MODE" == "--release" ]]; then
  python3 "$ROOT/scripts/release_check.py" --production
  PACKAGE_VERSION="$VERSION"
  CHANNEL="release"
elif [[ "$MODE" == "--candidate" ]]; then
  python3 "$ROOT/scripts/release_check.py"
  PACKAGE_VERSION="$VERSION-rc.2"
  CHANNEL="rc.2"
else
  echo "Usage: bash source/build.sh [--candidate|--release]" >&2
  exit 2
fi
APP="$ROOT/dist/Fix Clipboard.app"
mkdir -p "$ROOT/build" "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  xcrun swiftc "$ROOT/source/main.swift" "$ROOT/source/ProcessRunner.swift" "$ROOT/source/HomeUI.swift" "$ROOT/source/DiagnosticsUI.swift" "$ROOT/source/Licensing.swift" "$ROOT/source/ProUI.swift" "$ROOT/source/LicenseTests.swift" -target "${ARCH}-apple-macos13.0" -o "$ROOT/build/FixClipboard-$ARCH" -framework AppKit -framework Network -framework CoreWLAN -framework IOBluetooth -framework CoreBluetooth -framework Security -framework ServiceManagement -module-cache-path "${TMPDIR:-/tmp}/fix_clipboard_swift_cache"
done
xcrun lipo -create "$ROOT/build/FixClipboard-arm64" "$ROOT/build/FixClipboard-x86_64" -output "$APP/Contents/MacOS/FixClipboard"
python3 - "$APP" "$VERSION" "$BUILD" "$CHANNEL" <<'PY'
import plistlib, sys
from pathlib import Path
app, version, build, channel = sys.argv[1:]
info = dict(CFBundleExecutable='FixClipboard', CFBundleIdentifier='local.louis.fixclipboard',
    CFBundleIconFile='AppIcon', CFBundleName='Fix Clipboard', CFBundlePackageType='APPL',
    CFBundleShortVersionString=version, CFBundleVersion=build, FCReleaseChannel=channel,
    LSMinimumSystemVersion='13.0', LSUIElement=True, NSHighResolutionCapable=True,
    NSHumanReadableCopyright='© 2026 LouisLu888',
    NSBluetoothAlwaysUsageDescription='用于诊断蓝牙电源状态，帮助排查通用剪贴板问题；不会扫描或连接附近设备。')
with (Path(app) / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
PY
cp "$ROOT/config/Commerce.json" "$APP/Contents/Resources/Commerce.json"
cp "$ROOT/docs/PRIVACY.md" "$APP/Contents/Resources/PRIVACY.md"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
xcrun swift -module-cache-path "${TMPDIR:-/tmp}/fix_clipboard_swift_cache" "$ROOT/source/make-icon.swift" "$ROOT/build/AppIcon.iconset"
xcrun iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
"$APP/Contents/MacOS/FixClipboard" --self-test
"$APP/Contents/MacOS/FixClipboard" --license-self-test
codesign --verify --strict "$APP"
cp "$ROOT/INSTALL.md" "$ROOT/dist/INSTALL.md"
ZIP="$ROOT/dist/Fix-Clipboard-$PACKAGE_VERSION-universal.zip"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ZIP"
(cd "$ROOT/dist" && shasum -a 256 "Fix-Clipboard-$PACKAGE_VERSION-universal.zip" > SHA256SUMS.txt)
echo "Built $PACKAGE_VERSION ($CHANNEL)"
