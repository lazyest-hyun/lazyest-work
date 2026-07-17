#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Lazyest Work.app"
LEGACY_APP_NAME="GWSMenu.app"
INSTALL_SCOPE="system"
OPEN_AFTER_INSTALL=1
GOOGLE_RESTORE_ON_OPEN="auto"

usage() {
  cat <<USAGE
Usage: scripts/install-macos-app.sh [--user|--system] [--no-open] [--restore-google-on-open] [--skip-google-restore-on-open] [--distribution] [--ad-hoc]

Builds Lazyest Work and installs the app bundle.

Options:
  --system                  Install to /Applications (default, may require admin permissions)
  --user                    Install to ~/Applications
  --no-open                 Do not open the app after installing
  --restore-google-on-open  Restore Google sign-in from Keychain on the first launch after install
  --skip-google-restore-on-open
                            Skip Google sign-in restore once after install
  --distribution            Require the publisher Google OAuth configuration
  --ad-hoc                  Use ad-hoc signing. This can invalidate macOS Accessibility grants after rebuilds.

Environment variables accepted by scripts/build-macos-app.sh are forwarded:
  GWS_BUNDLE_ID
  GWS_BUILD_MODE
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
    --distribution)
      export GWS_BUILD_MODE="distribution"
      ;;
    --ad-hoc)
      echo "Warning: --ad-hoc can make macOS treat each rebuild as a different app for Accessibility." >&2
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
LEGACY_SYSTEM_APP="/Applications/$LEGACY_APP_NAME"
LEGACY_USER_APP="$HOME/Applications/$LEGACY_APP_NAME"

# Preserve a custom local bundle ID so URL callbacks, UserDefaults, and macOS
# privacy grants keep referring to the same app after a source update. Public
# distribution builds always use explicitly supplied publisher configuration.
if [[ "${GWS_BUILD_MODE:-local}" != "distribution" && -z "${GWS_BUNDLE_ID:-}" ]]; then
  for existing_app in "$DEST_APP" "$SYSTEM_APP" "$USER_APP" "$LEGACY_SYSTEM_APP" "$LEGACY_USER_APP"; do
    existing_plist="$existing_app/Contents/Info.plist"
    [[ -f "$existing_plist" ]] || continue
    existing_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$existing_plist" 2>/dev/null || true)"
    if [[ "$existing_bundle_id" =~ ^[A-Za-z0-9.-]+$ ]]; then
      export GWS_BUNDLE_ID="$existing_bundle_id"
      break
    fi
  done
fi

BUNDLE_ID="${GWS_BUNDLE_ID:-io.github.gwsmenu.app}"
HAD_EXISTING_APP=0
if [[ -d "$DEST_APP" || -d "$SYSTEM_APP" || -d "$USER_APP" || -d "$LEGACY_SYSTEM_APP" || -d "$LEGACY_USER_APP" ]]; then
  HAD_EXISTING_APP=1
fi

# A local rebuild may reuse the publisher Client ID already embedded in this
# developer's installed copy. Distribution builds never inherit bundle config.
if [[ "${GWS_BUILD_MODE:-local}" != "distribution" && -z "${GWS_GOOGLE_CLIENT_ID:-}" ]]; then
  for existing_app in "$DEST_APP" "$SYSTEM_APP" "$USER_APP" "$LEGACY_SYSTEM_APP" "$LEGACY_USER_APP"; do
    existing_plist="$existing_app/Contents/Info.plist"
    [[ -f "$existing_plist" ]] || continue
    existing_client_id="$(/usr/libexec/PlistBuddy -c 'Print :GIDClientID' "$existing_plist" 2>/dev/null || true)"
    if [[ "$existing_client_id" == *.apps.googleusercontent.com && "$existing_client_id" != *YOUR_GOOGLE_CLIENT_ID* ]]; then
      export GWS_GOOGLE_CLIENT_ID="$existing_client_id"
      break
    fi
  done
fi

BUILD_LOG="$(mktemp -t lazyest-work-build.XXXXXX)"
trap 'rm -f "$BUILD_LOG"' EXIT
"$ROOT_DIR/scripts/build-macos-app.sh" 2>&1 | tee "$BUILD_LOG"
BUILT_APP="$(tail -n 1 "$BUILD_LOG")"

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build did not produce an app bundle: $BUILT_APP" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"

if /usr/bin/pgrep -x "LazyestWork" >/dev/null 2>&1; then
  /usr/bin/pkill -x "LazyestWork" || true
  for _ in {1..20}; do
    if ! /usr/bin/pgrep -x "LazyestWork" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi
if /usr/bin/pgrep -x "GWSMenu" >/dev/null 2>&1; then
  /usr/bin/pkill -x "GWSMenu" || true
fi

if [[ -d "$DEST_APP" ]]; then
  rm -rf "$DEST_APP"
fi

/usr/bin/ditto "$BUILT_APP" "$DEST_APP"
for legacy_app in "$LEGACY_SYSTEM_APP" "$LEGACY_USER_APP"; do
  if [[ -d "$legacy_app" ]]; then
    rm -rf "$legacy_app"
  fi
done

if [[ "$INSTALL_SCOPE" == "system" && -d "$USER_APP" ]]; then
  rm -rf "$USER_APP"
fi

# Register the callback URL schemes embedded by the build.
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
    /usr/bin/defaults write "$BUNDLE_ID" gwsSkipGoogleRestoreOnce -bool true
  else
    /usr/bin/defaults delete "$BUNDLE_ID" gwsSkipGoogleRestoreOnce >/dev/null 2>&1 || true
  fi
  /usr/bin/open "$DEST_APP"
fi
