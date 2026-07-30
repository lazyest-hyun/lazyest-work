# Distribution Notes

## Public release

Public users install one signed and notarized app bundle. The publisher Google OAuth Client ID and callback scheme are embedded at build time, so the app's first-run flow is only:

```text
Connect Google -> Allow -> Done
```

Users never edit the app bundle or configure Google Cloud.

## Publisher Google configuration

- Enable Google Calendar API and Gmail API in the publisher project.
- Create the Google Apple-native OAuth client for the release bundle identifier, `com.lazyest.work`.
- Configure the external OAuth consent screen and complete the brand/data-access verification shown by Google Cloud for `calendar.events.readonly`.
- `gmail.labels` is a [non-sensitive Gmail scope](https://developers.google.com/workspace/gmail/api/auth/scopes), so this design does not require a restricted Gmail scope or its third-party security assessment.
- Do not create or bundle a Web client secret.

Build with:

```bash
GWS_BUILD_MODE=distribution \
GWS_GOOGLE_CLIENT_ID="<publisher-client-id>" \
GWS_CODESIGN_IDENTITY="Developer ID Application: ..." \
scripts/build-macos-app.sh --distribution
```

The reversed callback scheme is derived from the Client ID. A mismatched scheme, missing publisher ID, or non-Developer-ID signature fails the build. Direct Developer ID builds use the macOS file-based Keychain item named `auth`, so signed local and distribution builds restore the same Google session without a data-protection access group. They must not inject a custom `keychain-access-groups` entitlement.

For the GitHub Release artifact, store notarization credentials once with `notarytool store-credentials`, then package with the saved profile:

```bash
GWS_GOOGLE_CLIENT_ID="<publisher-client-id>" \
GWS_CODESIGN_IDENTITY="Developer ID Application: ... (<apple-team-id>)" \
GWS_INSTALLER_IDENTITY="Developer ID Installer: ... (<apple-team-id>)" \
GWS_NOTARY_PROFILE="lazyest-work-notary" \
scripts/package-macos-release.sh
```

`GWS_INSTALLER_IDENTITY` is required and must belong to the same Apple Team as
`GWS_CODESIGN_IDENTITY`; the script exits before building without it.

The packaging script signs the app with the hardened runtime and notarizes it as
a ZIP, then builds the installer package, notarizes and staples that, checks it
with the Installer Gatekeeper assessment, and writes a `.sha256` beside it. The
release artifact is `dist/LazyestWork-<version>-macOS.pkg` — the ZIP only exists
to get the app notarized, and README points users at the PKG.
`Apple Distribution` certificates are intentionally rejected because they are
for App Store workflows, not direct GitHub distribution.

Local development builds may reuse the publisher ID embedded in an existing `/Applications/Lazyest Work.app`. Distribution artifacts still require an explicit publisher ID at packaging time.

## Microsoft Graph

Teams status is optional. An unmanaged installation uses Microsoft 365 CLI once to authenticate through Microsoft's Azure CLI public client and create a single-tenant `Lazyest Work Personal` public client owned by the signed-in user. The creation command registers `http://localhost`, `User.Read`, and `Presence.ReadWrite` and never requests administrator consent. Lazyest Work then uses that generated client directly with OAuth authorization code, PKCE, and a temporary localhost callback. Public client and tenant IDs are stored in app preferences; the refresh credential is stored in Keychain.

The tenant must allow ordinary members to register apps and self-consent to these delegated permissions. This setup does not override tenant policy or Conditional Access. Managed builds may include `GWS_MICROSOFT_CLIENT_ID` and `GWS_MICROSOFT_TENANT_ID` only after that client has the app callback and delegated Graph permissions configured. The installer does not copy stale Microsoft client IDs from older app bundles.

## Security

- Google auth is handled by Google Sign-In and Keychain.
- Calendar uses `calendar.events.readonly` for the primary calendar's upcoming events.
- Gmail uses `gmail.labels` only for the Inbox unread count and does not send desktop mail alerts.
- Teams call block uses local macOS Accessibility and event monitoring permissions only when enabled.
- Teams status uses a user-owned public client and delegated Microsoft Graph access obtained through browser OAuth with PKCE. It sets user preferred presence and stores its refresh credential in Keychain.
- Generated Google product icons are ignored by Git.
- Public GitHub Release builds require Developer ID signing and notarization; local source builds do not.
