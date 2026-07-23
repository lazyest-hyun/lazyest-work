#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LazyestWork"
BUNDLE_ID="${GWS_BUNDLE_ID:-com.lazyest.work}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Lazyest Work.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/LazyestWork"

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# Preserve this developer machine's existing Google session configuration for
# local Run actions. Public artifacts always receive publisher config in CI.
if [[ -z "${GWS_GOOGLE_CLIENT_ID:-}" && -f "/Applications/Lazyest Work.app/Contents/Info.plist" ]]; then
  existing_client_id="$(/usr/libexec/PlistBuddy -c 'Print :GIDClientID' "/Applications/Lazyest Work.app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$existing_client_id" == *.apps.googleusercontent.com && "$existing_client_id" != *YOUR_GOOGLE_CLIENT_ID* ]]; then
    export GWS_GOOGLE_CLIENT_ID="$existing_client_id"
  fi
fi

"$ROOT_DIR/scripts/build-macos-app.sh"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..30}; do
      if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        exit 0
      fi
      sleep 0.1
    done
    echo "LazyestWork did not start." >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
