#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Fix Clipboard.app"
# Read the build's own version/channel so ZIP and DMG cannot silently disagree.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
CHANNEL=$(/usr/libexec/PlistBuddy -c 'Print FCReleaseChannel' "$APP/Contents/Info.plist")
if [[ "$CHANNEL" != "release" ]]; then VERSION="$VERSION-$CHANNEL"; fi
STAGE=$(mktemp -d "$ROOT/build/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
COPYFILE_DISABLE=1 /usr/bin/ditto --noextattr --noacl "$APP" "$STAGE/Fix Clipboard.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/INSTALL.md" "$STAGE/安装说明.md"
cp "$ROOT/docs/PRIVACY.md" "$STAGE/隐私说明.md"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
codesign --verify --strict "$STAGE/Fix Clipboard.app"
DMG="$ROOT/dist/Fix-Clipboard-$VERSION-universal.dmg"
hdiutil create -volname 'Fix Clipboard' -srcfolder "$STAGE" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd "$ROOT/dist" && shasum -a 256 "Fix-Clipboard-$VERSION-universal.zip" "Fix-Clipboard-$VERSION-universal.dmg" > SHA256SUMS.txt)
