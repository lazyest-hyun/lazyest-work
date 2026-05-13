#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GWSMenu.app"
INSTALL_SCOPE="user"
OPEN_AFTER_INSTALL=1

usage() {
  cat <<USAGE
Usage: scripts/install-macos-app.sh [--user|--system] [--no-open]

Builds GWS Menu and installs the app bundle.

Options:
  --user      Install to ~/Applications (default, no admin needed)
  --system    Install to /Applications (may require admin permissions)
  --no-open   Do not open the app after installing

Environment variables accepted by scripts/build-macos-app.sh are forwarded:
  GWS_BUNDLE_ID
  GWS_GOOGLE_CLIENT_ID
  GWS_GOOGLE_REVERSED_CLIENT_ID
  GWS_CODESIGN_IDENTITY
  GWS_TEAM_ID
  GWS_KEYCHAIN_ACCESS_GROUP
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      INSTALL_SCOPE="user"
      ;;
    --system)
      INSTALL_SCOPE="system"
      ;;
    --no-open)
      OPEN_AFTER_INSTALL=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if [[ "$INSTALL_SCOPE" == "system" ]]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
fi
DEST_APP="$INSTALL_DIR/$APP_NAME"
INFO_PLIST="$DEST_APP/Contents/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

read_info_value() {
  local key="$1"
  [[ -f "$INFO_PLIST" && -x "$PLIST_BUDDY" ]] || return 0
  "$PLIST_BUDDY" -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true
}

read_google_url_scheme() {
  [[ -f "$INFO_PLIST" && -x "$PLIST_BUDDY" ]] || return 0
  local type_index scheme_index scheme
  for type_index in {0..20}; do
    for scheme_index in {0..20}; do
      scheme="$("$PLIST_BUDDY" -c "Print :CFBundleURLTypes:$type_index:CFBundleURLSchemes:$scheme_index" "$INFO_PLIST" 2>/dev/null || true)"
      if [[ "$scheme" == com.googleusercontent.apps.* && "$scheme" != *YOUR_GOOGLE_CLIENT_ID* ]]; then
        echo "$scheme"
        return 0
      fi
    done
  done
}

if [[ -z "${GWS_BUNDLE_ID:-}" ]]; then
  EXISTING_BUNDLE_ID="$(read_info_value "CFBundleIdentifier")"
  if [[ -n "$EXISTING_BUNDLE_ID" ]]; then
    export GWS_BUNDLE_ID="$EXISTING_BUNDLE_ID"
  fi
fi

if [[ -z "${GWS_GOOGLE_CLIENT_ID:-}" ]]; then
  EXISTING_CLIENT_ID="$(read_info_value "GIDClientID")"
  if [[ "$EXISTING_CLIENT_ID" == *.apps.googleusercontent.com && "$EXISTING_CLIENT_ID" != *YOUR_GOOGLE_CLIENT_ID* ]]; then
    export GWS_GOOGLE_CLIENT_ID="$EXISTING_CLIENT_ID"
  fi
fi

if [[ -z "${GWS_GOOGLE_REVERSED_CLIENT_ID:-}" ]]; then
  EXISTING_REVERSED_CLIENT_ID="$(read_google_url_scheme)"
  if [[ -n "$EXISTING_REVERSED_CLIENT_ID" ]]; then
    export GWS_GOOGLE_REVERSED_CLIENT_ID="$EXISTING_REVERSED_CLIENT_ID"
  fi
fi
BUILD_LOG="$(mktemp -t gws-menu-build.XXXXXX)"
trap 'rm -f "$BUILD_LOG"' EXIT
"$ROOT_DIR/scripts/build-macos-app.sh" 2>&1 | tee "$BUILD_LOG"
BUILT_APP="$(tail -n 1 "$BUILD_LOG")"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build did not produce an app bundle: $BUILT_APP" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"

if /usr/bin/pgrep -x "GWSMenu" >/dev/null 2>&1; then
  /usr/bin/pkill -x "GWSMenu" || true
  for _ in {1..20}; do
    if ! /usr/bin/pgrep -x "GWSMenu" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

if [[ -d "$DEST_APP" ]]; then
  rm -rf "$DEST_APP"
fi

/usr/bin/ditto "$BUILT_APP" "$DEST_APP"

# Refresh Launch Services so URL-scheme changes from Open Setup are picked up.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
fi

echo "$DEST_APP"

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
  /usr/bin/open "$DEST_APP"
fi
