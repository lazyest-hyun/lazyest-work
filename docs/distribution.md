# Distribution Notes

## Free Source Install

Users can build and install locally:

```bash
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

This installs:

```text
/Applications/GWSMenu.app
```

This path does not require a DMG, notarization, or paid Apple Developer Program membership, but macOS may ask for admin approval when replacing the app bundle.

On first launch, users can enable **Teams call block** and **Open at login** before connecting Google. Teams call block is local-only: it needs macOS Accessibility/event-monitoring approval, not Microsoft Graph sign-in. Teams status is separate and uses Microsoft 365 CLI sign-in when the user connects Microsoft.

## Google Cloud

- Enable **Google Calendar API**.
- Optional: enable **Gmail API** for the Gmail unread badge.
- Create an OAuth client with application type **iOS**.
- Use the app Bundle ID shown in GWS Menu. The default is `io.github.gwsmenu.app`.
- Copy only the generated **Client ID**.
- Do not use a Web credential or any `client_secret`.

## Microsoft Graph

Teams status is optional. Without a native Microsoft client ID, GWS Menu uses Microsoft 365 CLI with Microsoft's first-party Microsoft Graph Command Line Tools app ID (`14d82eec-204b-4c2f-b7e8-296a70dab67e`). The installer does not preserve a Microsoft client ID from older app bundles; include `GWS_MICROSOFT_CLIENT_ID` and optionally `GWS_MICROSOFT_TENANT_ID` only when distributing a build with an organization-approved Microsoft Graph client.

## Security

- Google auth is handled by Google Sign-In and Keychain.
- Calendar access is read-only.
- The optional Gmail badge uses unread counts only and does not send desktop mail alerts.
- Teams call block uses local macOS Accessibility and event monitoring permissions only when enabled.
- Teams status uses Microsoft Graph delegated presence access through Microsoft 365 CLI unless the app bundle includes a native Microsoft client ID. It sets user preferred presence and relies on the selected backend's stored connection.
- Generated Google product icons are ignored by Git.
- A signed prebuilt app is optional and needs Apple Developer signing/notarization.
