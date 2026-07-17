#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Lazyest Work.app"
BUNDLE_ID="${GWS_BUNDLE_ID:-io.github.gwsmenu.app}"
GOOGLE_CLIENT_ID="${GWS_GOOGLE_CLIENT_ID:-}"
SIGNING_IDENTITY="${GWS_CODESIGN_IDENTITY:-}"
TEAM_ID="${GWS_TEAM_ID:-}"
KEYCHAIN_ACCESS_GROUP="${GWS_KEYCHAIN_ACCESS_GROUP:-}"
NOTARY_PROFILE="${GWS_NOTARY_PROFILE:-}"

die() {
  echo "error: $*" >&2
  exit 78
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"
}

[[ -n "$GOOGLE_CLIENT_ID" ]] || die "Set GWS_GOOGLE_CLIENT_ID to the publisher-owned Google Apple OAuth client ID."
[[ "$GOOGLE_CLIENT_ID" =~ ^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$ ]] ||
  die "GWS_GOOGLE_CLIENT_ID is not a valid Google Apple OAuth client ID."

[[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] ||
  die "Set GWS_CODESIGN_IDENTITY to a Developer ID Application identity."
[[ "$SIGNING_IDENTITY" =~ \(([A-Z0-9]{10})\)$ ]] ||
  die "GWS_CODESIGN_IDENTITY must include its Apple Team ID."
IDENTITY_TEAM_ID="${BASH_REMATCH[1]}"

[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Set GWS_TEAM_ID to the 10-character Apple Team ID."
[[ "$IDENTITY_TEAM_ID" == "$TEAM_ID" ]] ||
  die "GWS_TEAM_ID does not match the Developer ID Application identity."

if [[ -z "$KEYCHAIN_ACCESS_GROUP" ]]; then
  KEYCHAIN_ACCESS_GROUP="$TEAM_ID.$BUNDLE_ID"
fi
[[ "$KEYCHAIN_ACCESS_GROUP" == "$TEAM_ID."* ]] ||
  die "GWS_KEYCHAIN_ACCESS_GROUP must use the GWS_TEAM_ID prefix."

[[ -n "$NOTARY_PROFILE" ]] ||
  die "Set GWS_NOTARY_PROFILE to an existing notarytool Keychain profile."

for command_name in codesign ditto plutil security spctl xcrun; do
  require_command "$command_name"
done
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null

security find-identity -v -p codesigning 2>/dev/null |
  grep -F "\"$SIGNING_IDENTITY\"" >/dev/null ||
  die "Developer ID Application identity is not available in the current Keychain."

GWS_BUILD_MODE=distribution \
GWS_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
GWS_CODESIGN_IDENTITY="$SIGNING_IDENTITY" \
GWS_TEAM_ID="$TEAM_ID" \
GWS_KEYCHAIN_ACCESS_GROUP="$KEYCHAIN_ACCESS_GROUP" \
  "$ROOT_DIR/scripts/build-macos-app.sh" --distribution

[[ -d "$APP_DIR" ]] || die "Distribution build did not produce $APP_DIR."

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
SIGNATURE_INFO="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
grep -F "Authority=$SIGNING_IDENTITY" <<<"$SIGNATURE_INFO" >/dev/null ||
  die "Built app is not signed with the requested Developer ID Application identity."
grep -F "TeamIdentifier=$TEAM_ID" <<<"$SIGNATURE_INFO" >/dev/null ||
  die "Built app signature has an unexpected Apple Team ID."
grep -E '^CodeDirectory .*flags=.*runtime' <<<"$SIGNATURE_INFO" >/dev/null ||
  die "Built app does not have the hardened runtime enabled."

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_DIR/Contents/Info.plist")"
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || die "App version cannot be used in a release filename: $VERSION"
ZIP_PATH="${GWS_RELEASE_ZIP:-$ROOT_DIR/dist/LazyestWork-$VERSION-macOS.zip}"
mkdir -p "$(dirname "$ZIP_PATH")"

# notarytool receives a ZIP of the signed, unstapled app.
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
codesign --verify --deep --strict --verbose=4 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

# Replace the notarization upload with the release ZIP that contains the staple.
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$ZIP_PATH"
