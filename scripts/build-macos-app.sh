#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/GWSMenuBar"
APP_DIR="$ROOT_DIR/dist/GWSMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON="$PACKAGE_DIR/Assets/AppIcon.icns"
BUNDLE_ID="${GWS_BUNDLE_ID:-io.github.gwsmenu.app}"
GOOGLE_CLIENT_ID="${GWS_GOOGLE_CLIENT_ID:-YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com}"
GOOGLE_REVERSED_CLIENT_ID="${GWS_GOOGLE_REVERSED_CLIENT_ID:-com.googleusercontent.apps.YOUR_GOOGLE_CLIENT_ID}"
MICROSOFT_CLIENT_ID="${GWS_MICROSOFT_CLIENT_ID:-}"
MICROSOFT_TENANT_ID="${GWS_MICROSOFT_TENANT_ID:-organizations}"
MICROSOFT_REDIRECT_SCHEME="msauth.$BUNDLE_ID"
CODE_SIGN_IDENTITY="${GWS_CODESIGN_IDENTITY:-}"
TEAM_ID="${GWS_TEAM_ID:-}"

swift build --package-path "$PACKAGE_DIR" -c release -Xswiftc -gnone

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$PACKAGE_DIR/.build/release/GWSMenu" "$MACOS_DIR/GWSMenu"
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

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>GWSMenu</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>GWS Menu</string>
  <key>CFBundleDisplayName</key>
  <string>GWS Menu</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>GIDClientID</key>
  <string>$GOOGLE_CLIENT_ID</string>
$MICROSOFT_PLIST_KEYS
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
  <string>$GOOGLE_REVERSED_CLIENT_ID</string>
      </array>
    </dict>
$MICROSOFT_URL_TYPE
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  ENTITLEMENTS="$ROOT_DIR/dist/GWSMenu.entitlements"
  KEYCHAIN_GROUP="${GWS_KEYCHAIN_ACCESS_GROUP:-}"

  if [[ -z "$KEYCHAIN_GROUP" && -n "$TEAM_ID" ]]; then
    KEYCHAIN_GROUP="$TEAM_ID.$BUNDLE_ID"
  fi

  if [[ -n "$KEYCHAIN_GROUP" ]]; then
    cat > "$ENTITLEMENTS" <<ENTITLEMENTS_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>keychain-access-groups</key>
  <array>
    <string>$KEYCHAIN_GROUP</string>
  </array>
</dict>
</plist>
ENTITLEMENTS_PLIST
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_DIR"
  else
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
  fi
else
  codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
