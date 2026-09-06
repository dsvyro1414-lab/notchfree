#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
CONFIGURATION="${CONFIGURATION:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) echo 'CONFIGURATION must be debug or release' >&2; exit 2 ;; esac
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
swift build --disable-sandbox -c "$CONFIGURATION" --product NotchFree
BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"
STAGE_DIR="$(mktemp -d "$ROOT_DIR/.build/bundle.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
APP="$STAGE_DIR/NotchFree.app"
FRAMEWORK="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$FRAMEWORK/Versions/A/Resources"
cp "$BIN_DIR/NotchFree" "$APP/Contents/MacOS/NotchFree"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Vendor/MediaRemoteAdapter/bin/mediaremote-adapter.pl "$APP/Contents/Resources/"
cp Vendor/MediaRemoteAdapter/LICENSE "$APP/Contents/Resources/MediaRemoteAdapter-LICENSE"
cp LICENSE "$APP/Contents/Resources/NotchFree-LICENSE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ADAPTER="$ROOT_DIR/Vendor/MediaRemoteAdapter"
ARCH="$(uname -m)"
xcrun clang -dynamiclib -arch "$ARCH" -mmacosx-version-min=14.6 -fobjc-arc -fvisibility=default \
  -I "$ADAPTER/include" -I "$ADAPTER/src" \
  "$ADAPTER"/src/adapter/*.m "$ADAPTER"/src/private/*.m "$ADAPTER"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name '@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter' \
  -o "$FRAMEWORK/Versions/A/MediaRemoteAdapter"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FRAMEWORK/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"
codesign --force --sign - "$FRAMEWORK"
codesign --force --sign - --identifier com.dsvyro.notchfree "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
if [[ -L dist/NotchFree.app ]]; then echo 'Refusing to replace a symlink at dist/NotchFree.app' >&2; exit 1; fi
if [[ -e dist/NotchFree.app ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' dist/NotchFree.app/Contents/Info.plist)"
  [[ "$EXISTING_ID" == com.dsvyro.notchfree ]] || { echo 'Unexpected app at staging path'; exit 1; }
  rm -rf dist/NotchFree.app
fi
mv "$APP" dist/NotchFree.app
echo "Built $ROOT_DIR/dist/NotchFree.app ($ARCH; local ad-hoc signature)."
