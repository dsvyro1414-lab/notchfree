#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
command -v swift >/dev/null || { echo 'Install Apple Command Line Tools with: xcode-select --install'; exit 1; }
CONFIGURATION="${CONFIGURATION:-release}" ./scripts/build.sh
DESTINATION="${NOTCHFREE_INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$DESTINATION"
APP="$DESTINATION/NotchFree.app"
[[ ! -L "$APP" ]] || { echo 'Refusing to replace a symlink.' >&2; exit 1; }
if [[ -e "$APP" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
  [[ "$EXISTING_ID" == com.dsvyro.notchfree ]] || { echo 'A different app exists at the destination.'; exit 1; }
fi
pkill -x NotchFree 2>/dev/null || true
BACKUP="$DESTINATION/.NotchFree-previous.app"
[[ ! -e "$BACKUP" ]] || { echo "A previous backup exists at $BACKUP. Restore or move it first."; exit 1; }
if [[ -d "$APP" ]]; then mv "$APP" "$BACKUP"; fi
if ! ditto dist/NotchFree.app "$APP" || ! codesign --verify --deep --strict "$APP"; then
  if [[ -d "$APP" && ! -L "$APP" ]]; then rm -rf "$APP"; fi
  if [[ -d "$BACKUP" ]]; then mv "$BACKUP" "$APP"; fi
  echo 'Installation failed; previous app restored.' >&2; exit 1
fi
if [[ -d "$BACKUP" ]]; then rm -rf "$BACKUP"; fi
# Avoid a second discoverable copy of the same TCC identity after installation.
rm -rf dist/NotchFree.app
echo "Installed $APP"
if [[ "${NOTCHFREE_NO_OPEN:-0}" != 1 ]]; then open "$APP"; fi
