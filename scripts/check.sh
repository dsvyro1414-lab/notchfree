#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
swift run --disable-sandbox NotchFreeChecks
bash -n scripts/build.sh scripts/install.sh script/build_and_run.sh
plutil -lint Resources/Info.plist
