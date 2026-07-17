# Distribution Notes

## Public release

Public users install one signed and notarized app bundle. The publisher Google OAuth Client ID and callback scheme are embedded at build time, so the app's first-run flow is only:

```text
Connect Google -> Allow -> Done
```

Users never edit the app bundle or configure Google Cloud.

## Publisher Google configuration

- Enable Google Calendar API and Gmail API in the publisher project.
- Create an Apple-native OAuth client for the release Bundle ID.
- Configure the external OAuth consent screen and complete the brand/data-access verification shown by Google Cloud for `calendar.events.readonly`.
- `gmail.labels` is a [non-sensitive Gmail scope](https://developers.google.com/workspace/gmail/api/auth/scopes), so this design does not require a restricted Gmail scope or its third-party security assessment.
- Do not create or bundle a Web client secret.

Build with:

```bash
GWS_BUILD_MODE=distribution \
GWS_GOOGLE_CLIENT_ID="<publisher-client-id>" \
GWS_CODESIGN_IDENTITY="Developer ID Application: ..." \
GWS_TEAM_ID="<apple-team-id>" \
scripts/build-macos-app.sh --distribution
```

The reversed callback scheme is derived from the Client ID. A mismatched scheme, missing publisher ID, non-Developer-ID signature, or missing Keychain access group fails the build.

For the GitHub Release artifact, store notarization credentials once with `notarytool store-credentials`, then package with the saved profile:

```bash
GWS_GOOGLE_CLIENT_ID="<publisher-client-id>" \
GWS_CODESIGN_IDENTITY="Developer ID Application: ... (<apple-team-id>)" \
GWS_TEAM_ID="<apple-team-id>" \
GWS_NOTARY_PROFILE="lazyest-work-notary" \
scripts/package-macos-release.sh
```

The packaging script signs with the hardened runtime, submits the ZIP to Apple, staples the accepted ticket to the app, validates it with Gatekeeper, and then recreates the final release ZIP. `Apple Distribution` certificates are intentionally rejected because they are for App Store workflows, not direct GitHub distribution.

Local development builds may reuse the publisher ID embedded in an existing `/Applications/Lazyest Work.app`. This compatibility behavior is never used for a distribution artifact.

## Microsoft Graph

Teams status is optional. Without a native Microsoft client ID, Lazyest Work uses Microsoft 365 CLI with Microsoft's first-party Microsoft Graph Command Line Tools app ID (`14d82eec-204b-4c2f-b7e8-296a70dab67e`). The installer does not preserve a Microsoft client ID from older app bundles; include `GWS_MICROSOFT_CLIENT_ID` and optionally `GWS_MICROSOFT_TENANT_ID` only when distributing a build with an organization-approved Microsoft Graph client.

## Security

- Google auth is handled by Google Sign-In and Keychain.
- Calendar uses `calendar.events.readonly` for the primary calendar's upcoming events.
- Gmail uses `gmail.labels` only for the Inbox unread count and does not send desktop mail alerts.
- Teams call block uses local macOS Accessibility and event monitoring permissions only when enabled.
- Teams status uses Microsoft Graph delegated presence access through Microsoft 365 CLI unless the app bundle includes a native Microsoft client ID. It sets user preferred presence and relies on the selected backend's stored connection.
- Generated Google product icons are ignored by Git.
- Public GitHub Release builds require Developer ID signing and notarization; local source builds do not.
