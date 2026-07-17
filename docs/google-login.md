# Google Connection

## User flow

1. Open Lazyest Work.
2. Click **Connect Google**.
3. Allow Calendar events and the Gmail unread count.

Users do not create a Google Cloud project, install a CLI, paste a Client ID, or provide a client secret. Google Sign-In stores the session in Keychain and restores it after reboot.

Fresh installs enable the Gmail unread badge by default so Calendar and Gmail can be approved in the same Google flow. If Gmail permission is declined, Calendar remains connected and the Gmail badge turns off.

## Scopes

```text
https://www.googleapis.com/auth/calendar.events.readonly
https://www.googleapis.com/auth/gmail.labels
```

Google does not offer a read-only scope limited to one label count. `gmail.labels` is the narrowest non-sensitive scope that can read the Inbox label; although the scope can also edit labels, Lazyest Work only sends `GET /gmail/v1/users/me/labels/INBOX?fields=messagesUnread`. It does not request sender, subject, body, attachment, or message IDs.

Existing sessions that already granted the broader legacy `calendar.readonly` scope continue to work without a forced sign-in.

## Refresh behavior

- Calendar and Gmail refresh at launch, when the menu opens, and after wake or session activation.
- Calendar has a coalesced 15-minute safety refresh.
- Gmail has a coalesced 5-minute safety refresh while its badge is enabled.
- After Lazyest Work opens Gmail, unread reconciliation checks immediately, backs off while unchanged, and performs two short stable checks after a change. It is capped at seven requests and concurrent refreshes share one task.

## Publisher configuration

The publisher owns one Google Apple-native OAuth Client ID for the app Bundle ID. The build embeds that Client ID and its reversed callback scheme:

```bash
GWS_BUILD_MODE=distribution \
GWS_GOOGLE_CLIENT_ID="<publisher-client-id>" \
GWS_CODESIGN_IDENTITY="Developer ID Application: ..." \
GWS_TEAM_ID="<apple-team-id>" \
scripts/build-macos-app.sh --distribution
```

Distribution builds fail if the publisher Client ID, callback scheme, Developer ID Application identity, or Keychain access group is unavailable. Runtime bundle mutation and re-signing are intentionally unsupported. `scripts/package-macos-release.sh` performs notarization, ticket stapling, Gatekeeper validation, and final ZIP creation.
