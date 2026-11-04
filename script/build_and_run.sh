#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
CONFIG="${CONFIGURATION:-debug}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/ZeroTab.app"
case "$MODE" in
  run|--build-only|--verify|--debug|--logs|--telemetry) ;;
  *) echo "usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
cd "$ROOT_DIR"
if [[ "$MODE" != --build-only ]]; then
  /usr/bin/pkill -TERM -x ZeroTab >/dev/null 2>&1 || true
  for _ in {1..30}; do
    /usr/bin/pgrep -x ZeroTab >/dev/null || break
    sleep 0.1
  done
  if /usr/bin/pgrep -x ZeroTab >/dev/null; then
    echo "ZeroTab has not stopped. Quit it before rebuilding." >&2
    exit 1
  fi
fi
mkdir -p "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/.build/clang-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
SWIFT_OPTIONS=(--disable-sandbox --cache-path "$ROOT_DIR/.build/cache" --config-path "$ROOT_DIR/.build/config" --security-path "$ROOT_DIR/.build/security" --manifest-cache local)
swift build -c "$CONFIG" "${SWIFT_OPTIONS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path "${SWIFT_OPTIONS[@]}")"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/ZeroTab" "$APP_BUNDLE/Contents/MacOS/ZeroTab.new"
mv -f "$APP_BUNDLE/Contents/MacOS/ZeroTab.new" "$APP_BUNDLE/Contents/MacOS/ZeroTab"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$APP_BUNDLE/Contents/MacOS/ZeroTab"
# Use a local signing identity when configured; ad-hoc signing works for local development.
/usr/bin/codesign --force --sign "${ZEROTAB_SIGN_IDENTITY:--}" "$APP_BUNDLE"
case "$MODE" in
  --build-only) echo "$APP_BUNDLE" ;;
  run) /usr/bin/open "$APP_BUNDLE" ;;
  --verify) /usr/bin/open "$APP_BUNDLE"; sleep 1; /usr/bin/pgrep -x ZeroTab ;;
  --debug) /usr/bin/open "$APP_BUNDLE"; /usr/bin/lldb -n ZeroTab ;;
  --logs) /usr/bin/open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "ZeroTab"' ;;
  --telemetry) /usr/bin/open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "dev.hitomeng.ZeroTab"' ;;
esac
