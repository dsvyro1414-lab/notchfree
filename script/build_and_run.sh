#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry|--relaunch) ;; *) echo 'Usage: ./script/build_and_run.sh [--verify|--debug|--logs|--telemetry|--relaunch]'; exit 2 ;; esac
APP="$ROOT_DIR/dist/NotchFree.app"
if [[ "$MODE" != --relaunch ]]; then
  pkill -x NotchFree 2>/dev/null || true
  ./scripts/build.sh
fi
if [[ ! -d "$APP" && -d "$HOME/Applications/NotchFree.app" ]]; then APP="$HOME/Applications/NotchFree.app"; fi
[[ -d "$APP" ]] || { echo 'Build or install NotchFree first.'; exit 1; }
if [[ "$MODE" == --debug ]]; then exec lldb -- "$APP/Contents/MacOS/NotchFree"; fi
open "$APP"
case "$MODE" in
  --verify) sleep 2; pgrep -x NotchFree >/dev/null; echo 'NotchFree process is running.' ;;
  --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.dsvyro.notchfree"' ;;
esac
