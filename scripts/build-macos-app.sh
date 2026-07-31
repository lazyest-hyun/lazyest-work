#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/LazyestWork"
APP_DIR="$ROOT_DIR/dist/Lazyest Work.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON="$PACKAGE_DIR/Assets/AppIcon.icns"
BUNDLE_ID="${GWS_BUNDLE_ID:-com.lazyest.work}"
GOOGLE_CLIENT_ID="${GWS_GOOGLE_CLIENT_ID:-}"
GOOGLE_REVERSED_CLIENT_ID="${GWS_GOOGLE_REVERSED_CLIENT_ID:-}"
GOOGLE_PRODUCT_ICON_DOWNLOADS="${GWS_GOOGLE_PRODUCT_ICON_DOWNLOADS:-1}"
MICROSOFT_CLIENT_ID="${GWS_MICROSOFT_CLIENT_ID:-}"
MICROSOFT_TENANT_ID="${GWS_MICROSOFT_TENANT_ID:-organizations}"
MICROSOFT_REDIRECT_SCHEME="msauth.$BUNDLE_ID"
CODE_SIGN_IDENTITY="${GWS_CODESIGN_IDENTITY:-}"
BUILD_MODE="${GWS_BUILD_MODE:-local}"
APP_VERSION="${GWS_APP_VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
APP_BUILD_NUMBER="${GWS_APP_BUILD_NUMBER:-$(tr -d '[:space:]' < "$ROOT_DIR/BUILD_NUMBER")}"
# Reuse the established local signing identity when available. Changing the
# bundle identifier still requires fresh macOS privacy grants after migration.
LOCAL_CODE_SIGN_IDENTITY="GWS Menu Local Code Signing"
FALLBACK_LOCAL_CODE_SIGN_IDENTITY="MacBootstrap Local Code Signing"
USE_AD_HOC_SIGNING=0
CODESIGN_TIMESTAMP_ARGS=(--timestamp)

usage() {
  cat <<USAGE
Usage: scripts/build-macos-app.sh [--distribution]

Builds Lazyest Work into dist/Lazyest Work.app.

Options:
  --distribution  Require publisher Google OAuth configuration before building

Environment:
  GWS_BUILD_MODE=local|distribution
  GWS_GOOGLE_CLIENT_ID=<publisher-owned Apple OAuth client ID>
  GWS_GOOGLE_REVERSED_CLIENT_ID=<optional; derived from the client ID when omitted>
  GWS_GOOGLE_PRODUCT_ICON_DOWNLOADS=0|1 (default: 1)
  GWS_APP_VERSION=<optional override for VERSION>
  GWS_APP_BUILD_NUMBER=<optional override for BUILD_NUMBER>
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --distribution)
      BUILD_MODE="distribution"
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

case "$BUILD_MODE" in
  local|distribution)
    ;;
  *)
    echo "GWS_BUILD_MODE must be 'local' or 'distribution' (got: $BUILD_MODE)." >&2
    exit 64
    ;;
esac

case "$GOOGLE_PRODUCT_ICON_DOWNLOADS" in
  0|1)
    ;;
  *)
    echo "GWS_GOOGLE_PRODUCT_ICON_DOWNLOADS must be 0 or 1." >&2
    exit 64
    ;;
esac

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; then
  echo "App version must use major.minor.patch format (got: $APP_VERSION)." >&2
  exit 64
fi

if [[ ! "$APP_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "App build number must be a positive integer (got: $APP_BUILD_NUMBER)." >&2
  exit 64
fi

case "$CODE_SIGN_IDENTITY" in
  -|ad-hoc|adhoc)
    CODE_SIGN_IDENTITY=""
    USE_AD_HOC_SIGNING=1
    ;;
esac

if [[ "$USE_AD_HOC_SIGNING" -eq 0 && -z "$CODE_SIGN_IDENTITY" && "$BUILD_MODE" == "distribution" ]]; then
  CODE_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' |
      sed -n '1p'
  )"
fi

if [[ "$USE_AD_HOC_SIGNING" -eq 0 && -z "$CODE_SIGN_IDENTITY" && "$BUILD_MODE" == "local" ]] &&
  security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$LOCAL_CODE_SIGN_IDENTITY\"" >/dev/null; then
  CODE_SIGN_IDENTITY="$LOCAL_CODE_SIGN_IDENTITY"
fi

if [[ "$USE_AD_HOC_SIGNING" -eq 0 && -z "$CODE_SIGN_IDENTITY" && "$BUILD_MODE" == "local" ]] &&
  security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$FALLBACK_LOCAL_CODE_SIGN_IDENTITY\"" >/dev/null; then
  CODE_SIGN_IDENTITY="$FALLBACK_LOCAL_CODE_SIGN_IDENTITY"
fi

if [[ "$CODE_SIGN_IDENTITY" == "$LOCAL_CODE_SIGN_IDENTITY" || "$CODE_SIGN_IDENTITY" == "$FALLBACK_LOCAL_CODE_SIGN_IDENTITY" ]]; then
  CODESIGN_TIMESTAMP_ARGS=(--timestamp=none)
fi

# A Developer ID signature always produces a direct-distribution artifact,
# even if the caller forgot the explicit flag. Apple Distribution identities
# are for App Store workflows and are intentionally rejected here.
case "$CODE_SIGN_IDENTITY" in
  Developer\ ID\ Application:*)
    BUILD_MODE="distribution"
    ;;
  Apple\ Distribution:*)
    echo "Apple Distribution signing is not valid for a direct GitHub Release; use Developer ID Application." >&2
    exit 64
    ;;
esac

GOOGLE_OAUTH_ENABLED=0
if [[ -n "$GOOGLE_CLIENT_ID" || -n "$GOOGLE_REVERSED_CLIENT_ID" ]]; then
  if [[ ! "$GOOGLE_CLIENT_ID" =~ ^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$ ]] ||
    [[ "$GOOGLE_CLIENT_ID" == *YOUR_GOOGLE_CLIENT_ID* ]]; then
    echo "GWS_GOOGLE_CLIENT_ID is not a valid Google Apple OAuth client ID." >&2
    exit 64
  fi

  EXPECTED_REVERSED_CLIENT_ID="com.googleusercontent.apps.${GOOGLE_CLIENT_ID%.apps.googleusercontent.com}"
  if [[ -z "$GOOGLE_REVERSED_CLIENT_ID" ]]; then
    GOOGLE_REVERSED_CLIENT_ID="$EXPECTED_REVERSED_CLIENT_ID"
  elif [[ "$GOOGLE_REVERSED_CLIENT_ID" != "$EXPECTED_REVERSED_CLIENT_ID" ]]; then
    echo "GWS_GOOGLE_REVERSED_CLIENT_ID does not match GWS_GOOGLE_CLIENT_ID." >&2
    exit 64
  fi
  GOOGLE_OAUTH_ENABLED=1
elif [[ "$BUILD_MODE" == "distribution" ]]; then
  echo "Distribution build requires the publisher-owned GWS_GOOGLE_CLIENT_ID." >&2
  echo "Set it in the release build environment; users must never provide their own Client ID." >&2
  exit 78
else
  echo "Note: Google OAuth is not configured; building a local app with Google features unavailable." >&2
fi

if [[ "$BUILD_MODE" == "distribution" ]]; then
  case "$CODE_SIGN_IDENTITY" in
    Developer\ ID\ Application:*)
      ;;
    *)
      echo "Distribution build requires a Developer ID Application signing identity." >&2
      exit 78
      ;;
  esac

fi

if [[ -n "${GWS_KEYCHAIN_ACCESS_GROUP:-}" ]]; then
  echo "GWS_KEYCHAIN_ACCESS_GROUP is not supported: Developer ID direct-distribution builds use the macOS file-based Keychain." >&2
  echo "Do not inject keychain-access-groups without an entitlement-authorized provisioning workflow." >&2
  exit 64
fi

SWIFT_BUILD_ARGS=(
  --package-path "$PACKAGE_DIR"
  -c release
  -Xswiftc -gnone
  -Xswiftc -DGWS_FILE_KEYCHAIN
)
swift build "${SWIFT_BUILD_ARGS[@]}"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$PACKAGE_DIR/.build/release/LazyestWork" "$MACOS_DIR/LazyestWork"
if [[ ! -f "$APP_ICON" ]]; then
  "$ROOT_DIR/scripts/generate-app-icon.swift" >/dev/null
fi
cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
for bundle in "$PACKAGE_DIR"/.build/*-apple-macosx/release/*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$RESOURCES_DIR/"
done

MICROSOFT_PLIST_KEYS=""
MICROSOFT_URL_TYPE=""
GOOGLE_PLIST_KEYS=""
GOOGLE_URL_TYPE=""
if [[ "$GOOGLE_OAUTH_ENABLED" -eq 1 ]]; then
  GOOGLE_PLIST_KEYS="  <key>GIDClientID</key>
  <string>$GOOGLE_CLIENT_ID</string>"
  GOOGLE_URL_TYPE="    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>$GOOGLE_REVERSED_CLIENT_ID</string>
      </array>
    </dict>"
fi

if [[ -n "$MICROSOFT_CLIENT_ID" ]]; then
  MICROSOFT_PLIST_KEYS="  <key>GWSMicrosoftClientID</key>
  <string>$MICROSOFT_CLIENT_ID</string>
  <key>GWSMicrosoftTenantID</key>
  <string>$MICROSOFT_TENANT_ID</string>"
  MICROSOFT_URL_TYPE="    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>$MICROSOFT_REDIRECT_SCHEME</string>
      </array>
    </dict>"
fi

URL_TYPES_PLIST=""
if [[ -n "$GOOGLE_URL_TYPE" || -n "$MICROSOFT_URL_TYPE" ]]; then
  URL_TYPES_PLIST="  <key>CFBundleURLTypes</key>
  <array>
$GOOGLE_URL_TYPE
$MICROSOFT_URL_TYPE
  </array>"
fi

if [[ "$GOOGLE_PRODUCT_ICON_DOWNLOADS" -eq 1 ]]; then
  GOOGLE_PRODUCT_ICON_DOWNLOADS_PLIST_VALUE="<true/>"
else
  GOOGLE_PRODUCT_ICON_DOWNLOADS_PLIST_VALUE="<false/>"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>LazyestWork</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Lazyest Work</string>
  <key>CFBundleDisplayName</key>
  <string>Lazyest Work</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_NUMBER</string>
  <key>GWSWorkspaceIconDownloadsEnabled</key>
  $GOOGLE_PRODUCT_ICON_DOWNLOADS_PLIST_VALUE
$GOOGLE_PLIST_KEYS
$MICROSOFT_PLIST_KEYS
$URL_TYPES_PLIST
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  # Google Sign-In uses the macOS file-based Keychain so the direct-distribution
  # app does not depend on a data-protection access group or provisioning
  # profile. Do not add keychain-access-groups to this Developer ID build.
  codesign --force --options runtime "${CODESIGN_TIMESTAMP_ARGS[@]}" --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
else
  if [[ "$BUILD_MODE" == "distribution" ]]; then
    echo "Distribution build requires a Developer ID Application signing identity." >&2
    exit 78
  fi
  codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
