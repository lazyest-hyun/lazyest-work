#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="GWSMenu.app"
INSTALL_SCOPE="system"
OPEN_AFTER_INSTALL=1
GOOGLE_RESTORE_ON_OPEN="auto"

usage() {
  cat <<USAGE
Usage: scripts/install-macos-app.sh [--user|--system] [--no-open] [--restore-google-on-open] [--skip-google-restore-on-open] [--ad-hoc]

Builds GWS Menu and installs the app bundle.

Options:
  --system                  Install to /Applications (default, may require admin permissions)
  --user                    Install to ~/Applications
  --no-open                 Do not open the app after installing
  --restore-google-on-open  Restore Google sign-in from Keychain on the first launch after install
  --skip-google-restore-on-open
                            Skip Google sign-in restore once after install
  --ad-hoc                  Use ad-hoc signing. This can invalidate macOS Accessibility/Input Monitoring grants after rebuilds.

Environment variables accepted by scripts/build-macos-app.sh are forwarded:
  GWS_BUNDLE_ID
  GWS_GOOGLE_CLIENT_ID
  GWS_GOOGLE_REVERSED_CLIENT_ID
  GWS_MICROSOFT_CLIENT_ID
  GWS_MICROSOFT_TENANT_ID
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
    --restore-google-on-open)
      GOOGLE_RESTORE_ON_OPEN="restore"
      ;;
    --skip-google-restore-on-open)
      GOOGLE_RESTORE_ON_OPEN="skip"
      ;;
    --ad-hoc)
      echo "Warning: --ad-hoc can make macOS treat each rebuild as a different app for Accessibility/Input Monitoring." >&2
      export GWS_CODESIGN_IDENTITY="-"
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
SYSTEM_APP="/Applications/$APP_NAME"
USER_APP="$HOME/Applications/$APP_NAME"
HAD_EXISTING_APP=0
if [[ -d "$DEST_APP" || -d "$SYSTEM_APP" || -d "$USER_APP" ]]; then
  HAD_EXISTING_APP=1
fi
EXISTING_INFO_PLISTS=("$DEST_APP/Contents/Info.plist")
if [[ "$DEST_APP" != "$USER_APP" ]]; then
  EXISTING_INFO_PLISTS+=("$USER_APP/Contents/Info.plist")
fi
if [[ "$DEST_APP" != "$SYSTEM_APP" ]]; then
  EXISTING_INFO_PLISTS+=("$SYSTEM_APP/Contents/Info.plist")
fi
PLIST_BUDDY="/usr/libexec/PlistBuddy"

read_info_value() {
  local key="$1"
  [[ -x "$PLIST_BUDDY" ]] || return 0
  local plist value
  for plist in "${EXISTING_INFO_PLISTS[@]}"; do
    [[ -f "$plist" ]] || continue
    value="$("$PLIST_BUDDY" -c "Print :$key" "$plist" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
  done
}

read_google_url_scheme() {
  [[ -x "$PLIST_BUDDY" ]] || return 0
  local plist type_index scheme_index scheme
  for plist in "${EXISTING_INFO_PLISTS[@]}"; do
    [[ -f "$plist" ]] || continue
    for type_index in {0..20}; do
      for scheme_index in {0..20}; do
        scheme="$("$PLIST_BUDDY" -c "Print :CFBundleURLTypes:$type_index:CFBundleURLSchemes:$scheme_index" "$plist" 2>/dev/null || true)"
        if [[ "$scheme" == com.googleusercontent.apps.* && "$scheme" != *YOUR_GOOGLE_CLIENT_ID* ]]; then
          echo "$scheme"
          return 0
        fi
      done
    done
  done
}

if [[ -z "${GWS_BUNDLE_ID:-}" ]]; then
  EXISTING_BUNDLE_ID="$(read_info_value "CFBundleIdentifier")"
  if [[ -n "$EXISTING_BUNDLE_ID" ]]; then
    export GWS_BUNDLE_ID="$EXISTING_BUNDLE_ID"
  fi
fi

if [[ -z "${GWS_BUNDLE_ID:-}" ]]; then
  export GWS_BUNDLE_ID="io.github.gwsmenu.app"
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

if [[ "$INSTALL_SCOPE" == "system" && -d "$USER_APP" ]]; then
  rm -rf "$USER_APP"
fi

# Refresh Launch Services so URL-scheme changes from Open Setup are picked up.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
fi

echo "$DEST_APP"

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
  SKIP_GOOGLE_RESTORE_ON_OPEN=0
  case "$GOOGLE_RESTORE_ON_OPEN" in
    skip)
      SKIP_GOOGLE_RESTORE_ON_OPEN=1
      ;;
    restore)
      SKIP_GOOGLE_RESTORE_ON_OPEN=0
      ;;
    auto)
      if [[ "$HAD_EXISTING_APP" -eq 0 ]]; then
        SKIP_GOOGLE_RESTORE_ON_OPEN=1
      fi
      ;;
  esac

  if [[ "$SKIP_GOOGLE_RESTORE_ON_OPEN" -eq 1 ]]; then
    /usr/bin/defaults write "$GWS_BUNDLE_ID" gwsSkipGoogleRestoreOnce -bool true
  else
    /usr/bin/defaults delete "$GWS_BUNDLE_ID" gwsSkipGoogleRestoreOnce >/dev/null 2>&1 || true
  fi
  /usr/bin/open "$DEST_APP"
fi
