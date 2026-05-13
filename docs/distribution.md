# Distribution Notes

## Free Source Install

Users can build and install locally:

```bash
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

This installs:

```text
~/Applications/GWSMenu.app
```

This path does not require a DMG, notarization, or paid Apple Developer Program membership.

## Google Cloud

- Enable **Google Calendar API**.
- Optional: enable **Gmail API** for the Gmail unread badge.
- Create an OAuth client with application type **iOS**.
- Use the app Bundle ID shown in GWS Menu. The default is `io.github.gwsmenu.app`.
- Copy only the generated **Client ID**.
- Do not use a Web credential or any `client_secret`.

## Security

- Google auth is handled by Google Sign-In and Keychain.
- Calendar access is read-only.
- The optional Gmail badge uses unread counts only and does not send desktop mail alerts.
- Generated Google product icons are ignored by Git.
- A signed prebuilt app is optional and needs Apple Developer signing/notarization.
