#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Lazyest Work.app"
BUNDLE_ID="${GWS_BUNDLE_ID:-com.lazyest.work}"
GOOGLE_CLIENT_ID="${GWS_GOOGLE_CLIENT_ID:-}"
SIGNING_IDENTITY="${GWS_CODESIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${GWS_INSTALLER_IDENTITY:-}"
NOTARY_PROFILE="${GWS_NOTARY_PROFILE:-}"

die() {
  echo "error: $*" >&2
  exit 78
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"
}

run_apple_network_tool() {
  env \
    -u SSL_CERT_FILE \
    -u CURL_CA_BUNDLE \
    -u REQUESTS_CA_BUNDLE \
    -u GIT_SSL_CAINFO \
    -u NODE_EXTRA_CA_CERTS \
    -u AWS_CA_BUNDLE \
    -u M2T_AWS_CA_BUNDLE \
    -u M2T_DOCKER_EXTRA_CA_CERTS \
    "$@"
}

staple_with_retry() {
  local target="$1"
  local attempt
  for attempt in 1 2 3; do
    if run_apple_network_tool xcrun stapler staple "$target"; then
      return
    fi
    if ((attempt < 3)); then
      echo "warning: stapler attempt $attempt failed; retrying" >&2
      sleep 2
    fi
  done
  return 1
}

[[ -n "$GOOGLE_CLIENT_ID" ]] || die "Set GWS_GOOGLE_CLIENT_ID to the publisher-owned Google Apple OAuth client ID."
[[ "$GOOGLE_CLIENT_ID" =~ ^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$ ]] ||
  die "GWS_GOOGLE_CLIENT_ID is not a valid Google Apple OAuth client ID."

[[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] ||
  die "Set GWS_CODESIGN_IDENTITY to a Developer ID Application identity."
[[ "$SIGNING_IDENTITY" =~ \(([A-Z0-9]{10})\)$ ]] ||
  die "GWS_CODESIGN_IDENTITY must include its Apple Team ID."
IDENTITY_TEAM_ID="${BASH_REMATCH[1]}"
[[ "$INSTALLER_IDENTITY" == "Developer ID Installer:"* ]] ||
  die "Set GWS_INSTALLER_IDENTITY to a Developer ID Installer identity."
[[ "$INSTALLER_IDENTITY" == *"($IDENTITY_TEAM_ID)" ]] ||
  die "GWS_INSTALLER_IDENTITY must belong to the same Apple Team as GWS_CODESIGN_IDENTITY."

[[ -n "$NOTARY_PROFILE" ]] ||
  die "Set GWS_NOTARY_PROFILE to an existing notarytool Keychain profile."

for command_name in codesign ditto pkgbuild pkgutil plutil security shasum spctl xcrun; do
  require_command "$command_name"
done
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null

security find-identity -v -p codesigning 2>/dev/null |
  grep -F "\"$SIGNING_IDENTITY\"" >/dev/null ||
  die "Developer ID Application identity is not available in the current Keychain."
security find-identity -v -p basic 2>/dev/null |
  grep -F "\"$INSTALLER_IDENTITY\"" >/dev/null ||
  die "Developer ID Installer identity is not available in the current Keychain."

GWS_BUILD_MODE=distribution \
GWS_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
GWS_CODESIGN_IDENTITY="$SIGNING_IDENTITY" \
  "$ROOT_DIR/scripts/build-macos-app.sh" --distribution

[[ -d "$APP_DIR" ]] || die "Distribution build did not produce $APP_DIR."

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
SIGNATURE_INFO="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
grep -F "Authority=$SIGNING_IDENTITY" <<<"$SIGNATURE_INFO" >/dev/null ||
  die "Built app is not signed with the requested Developer ID Application identity."
grep -F "TeamIdentifier=$IDENTITY_TEAM_ID" <<<"$SIGNATURE_INFO" >/dev/null ||
  die "Built app signature has an unexpected Apple Team ID."
grep -E '^CodeDirectory .*flags=.*runtime' <<<"$SIGNATURE_INFO" >/dev/null ||
  die "Built app does not have the hardened runtime enabled."

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_DIR/Contents/Info.plist")"
[[ "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || die "App version cannot be used in a release filename: $VERSION"
ZIP_PATH="${GWS_RELEASE_ZIP:-$ROOT_DIR/dist/LazyestWork-$VERSION-macOS.zip}"
PKG_PATH="${GWS_RELEASE_PKG:-$ROOT_DIR/dist/LazyestWork-$VERSION-macOS.pkg}"
mkdir -p "$(dirname "$ZIP_PATH")"
mkdir -p "$(dirname "$PKG_PATH")"

# notarytool receives a ZIP of the signed, unstapled app.
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
run_apple_network_tool xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

staple_with_retry "$APP_DIR"
if ! run_apple_network_tool xcrun stapler validate "$APP_DIR"; then
  echo "warning: stapler validation could not reach Apple's ticket service; continuing to required Gatekeeper assessment" >&2
fi
codesign --verify --deep --strict --verbose=4 "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR"

# The ZIP exists only to obtain and staple the app notarization ticket.
rm -f "$ZIP_PATH"
rm -f "$PKG_PATH" "$PKG_PATH.sha256"
pkgbuild \
  --component "$APP_DIR" \
  --install-location "/Applications" \
  --identifier "$BUNDLE_ID.pkg" \
  --version "$VERSION" \
  --sign "$INSTALLER_IDENTITY" \
  "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH" >/dev/null
run_apple_network_tool xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
staple_with_retry "$PKG_PATH"
if ! run_apple_network_tool xcrun stapler validate "$PKG_PATH"; then
  echo "warning: stapler validation could not reach Apple's PKG ticket service; continuing to required Installer Gatekeeper assessment" >&2
fi
spctl --assess --type install --verbose=4 "$PKG_PATH"
shasum -a 256 "$PKG_PATH" >"$PKG_PATH.sha256"

printf '%s\n' "$PKG_PATH" "$PKG_PATH.sha256"
