# Lazyest Work

Native macOS menu bar app for Google Workspace shortcuts, read-only Google Calendar, meeting alerts, and an optional Gmail unread badge.

![Lazyest Work setup card](docs/screenshots/menu-setup-card.png)

## What It Does

- Opens Gmail, Calendar, Meet, Chat, Drive, Docs, Sheets, Slides, and custom Google services from the menu bar.
- Shows your upcoming Google Calendar events and the current or next meeting in the menu bar.
- Sends optional macOS desktop alerts before meetings.
- Can turn on Do Not Disturb during accepted meetings.
- Can ask for confirmation before Microsoft Teams outgoing call buttons and block Control-scroll zoom in Teams.
- Can set Microsoft Teams status to Busy during accepted meetings through Microsoft Graph when delegated presence consent is available.
- Shows an optional Gmail Inbox unread badge, capped as `99+`.
- Stores Google and Microsoft refresh credentials in Keychain.

## Install

Install the signed and notarized PKG from
[GitHub Releases](https://github.com/lazyest-hyun/lazyest-work/releases/latest).
The installer places Lazyest Work in `/Applications`.

Lazyest Work uses the dedicated `com.lazyest.work` bundle identifier. The first install after migrating from GWS Menu needs fresh macOS permissions and a new Google sign-in. Fresh source builds also need publisher Google OAuth configuration before Google sign-in is available.

For local development:

```bash
git clone https://github.com/lazyest-hyun/lazyest-work.git
cd lazyest-work
GWS_GOOGLE_CLIENT_ID="<publisher-client-id>" \
  swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

This builds, installs to `/Applications/Lazyest Work.app`, and opens the app. A Google native-app Client ID is public configuration, not a secret; the app never bundles a client secret.

## Connect Google

1. Open Lazyest Work.
2. Click **Connect Google**.
3. Allow Calendar events and the Gmail unread count.

That is the complete user setup. The session is restored from Keychain after reboot.

The Gmail badge is enabled by default on a fresh install. It reads only the Inbox unread count, not sender, subject, body, attachments, or message IDs. After Lazyest Work opens Gmail, it briefly rechecks the count with bounded backoff and stops after the new count settles.

Optional features remain separate:

- **Teams call block**: local macOS permission; no Microsoft sign-in.
- **Open at login**: adds Lazyest Work to Login Items.
- **Meeting alerts**: requests macOS notification permission when enabled.
- **Do Not Disturb during meetings**: one-time macOS Shortcuts approval when enabled.
- **Teams Busy**: optional Microsoft connection.

## Settings

Open Settings from the gear button in Lazyest Work. Changes save automatically.

- **Calendar & Mail**: meeting alerts, Do Not Disturb, and the Gmail unread badge.
- **Teams call block**: require confirmation before supported Teams outgoing call buttons and block Control-scroll zoom inside Teams.
- **Teams status**: optional Microsoft Graph integration through browser sign-in.
- **General**: enable Open at login or open the GitHub repository.
- **Account**: connect or sign out of Google.

To customize Workspace shortcuts, click the sliders button next to the **Workspace** label on the main menu. The editor uses the same grid layout as the menu.

### Do Not Disturb During Meetings

Lazyest Work can turn on macOS Do Not Disturb during accepted meetings.

1. Open **Settings -> Calendar & Mail**.
2. Turn on **Do Not Disturb during meetings**.
3. If an **Approve** button appears, click it, then click **Add Shortcut** once in macOS.
4. Return to Lazyest Work. The setting turns on automatically after approval.

Only current accepted meetings with a meeting link or guests trigger Focus. Tentative, unanswered, and declined meetings only show their status color in Upcoming.
If Do Not Disturb was already on before a meeting starts, Lazyest Work leaves it on after the meeting ends.

### Teams Status During Meetings

Lazyest Work can set your Teams preferred presence to `Busy / Busy` during accepted Google Calendar meetings.

1. Open **Settings -> Teams status**.
2. Install **Microsoft 365 CLI** once if the settings card asks for it.
3. Click **Sign in**. The first sign-in uses Microsoft 365 CLI and the browser to create a single-tenant `Lazyest Work Personal` public client owned by your work account.
4. Sign in again to that personal client and allow profile and Teams presence access. Lazyest Work stores the refresh credential in Keychain.

The one-time setup authenticates the real Microsoft 365 CLI through Microsoft's pre-authorized Azure CLI public client, then creates the personal app without requesting administrator consent. The bootstrap credential can carry broad directory-write permissions, so setup runs with an owner-only temporary CLI home and removes it when setup finishes. It does not add, remove, or switch the user's existing `m365` connections. The personal app registers only `User.Read` and `Presence.ReadWrite`; Lazyest Work requests those delegated permissions plus offline refresh access with PKCE and a temporary localhost callback. The generated client and tenant IDs are stored in app preferences, and the refresh credential is stored in Keychain.

This works for ordinary organization members only when their tenant allows users to register apps and self-consent to these delegated permissions, and while Microsoft continues to pre-authorize the Azure CLI public client for the required directory operation. It does not bypass tenant or Conditional Access policy. A managed build can instead set `GWS_MICROSOFT_CLIENT_ID` and `GWS_MICROSOFT_TENANT_ID` after the organization configures that client and its callback.

If the personal app is deleted from Entra ID, click **Set up again**, then **Sign in**. Cancelling sign-in or encountering a temporary network error does not delete an existing Microsoft credential.

The settings card shows whether Lazyest Work set Teams preferred status to Busy, kept an existing Lazyest Work Busy value, cleared it, or is waiting for an active accepted meeting. Teams can take a few minutes to show a successful Microsoft Graph presence update.

Lazyest Work calls Microsoft Graph `setUserPreferredPresence` while a qualifying meeting is active and `clearUserPreferredPresence` when the meeting ends, the setting is turned off, or Microsoft is signed out.

### Teams Call Block

Teams call block is local-only and does not require Microsoft sign-in.

1. Open **Settings -> Teams call block**.
2. Turn on **Teams call block**.
3. If macOS permission is missing, turning the toggle on opens System Settings. Enable **Lazyest Work** there, then Lazyest Work turns the feature on automatically.

Lazyest Work blocks only Teams elements whose accessibility role and label identify an outgoing call action, such as **Meet now**, **Audio call**, **Video call**, **음성 통화**, or **영상 통화**. It does not intentionally block dropdown buttons, hang-up buttons, chat/profile buttons, or Teams status sync.

## Updating

Public builds update from the signed and notarized PKG in GitHub Releases. Open the PKG and click **Continue**, then **Install**; the Installer places Lazyest Work in `/Applications`. Source builds can update manually:

```bash
git pull
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

The installer closes any running `LazyestWork` process, replaces `/Applications/Lazyest Work.app`, removes an older `~/Applications/Lazyest Work.app` copy when present, and opens the new version.

### Release package

Create the public PKG only on a Mac with the Developer ID Application and Developer ID Installer identities, the publisher-owned Google client ID, and a validated notarytool Keychain profile:

```bash
GWS_GOOGLE_CLIENT_ID="..." \
GWS_CODESIGN_IDENTITY="Developer ID Application: ..." \
GWS_INSTALLER_IDENTITY="Developer ID Installer: ..." \
GWS_NOTARY_PROFILE="lazyest-notary" \
scripts/package-macos-release.sh
```

The command creates `dist/LazyestWork-<version>-macOS.pkg` and its SHA-256 file. It does not create a GitHub tag or Release.

## Privacy and Permissions

- Calendar access uses `https://www.googleapis.com/auth/calendar.events.readonly`.
- The Gmail badge uses the non-sensitive `https://www.googleapis.com/auth/gmail.labels` scope only when enabled. Google defines it as label read/write access; Lazyest Work only performs a read of the Inbox `messagesUnread` field because Google offers no count-only scope.
- Teams status requests Microsoft Graph delegated `User.Read` and `Presence.ReadWrite` access through browser sign-in.
- Teams call block uses macOS Accessibility and event monitoring permissions only when enabled. It does not require Microsoft Graph or Teams sign-in.
- Lazyest Work does not read Gmail sender, subject, body, attachments, or message IDs.
- Lazyest Work does not send desktop mail alerts.
- Do Not Disturb during meetings uses macOS Do Not Disturb; your Focus settings decide which apps or people are allowed through.
- Lazyest Work does not turn off a Do Not Disturb state that was already active before it touched it.
- Google auth is handled by Google Sign-In and Keychain.
- Microsoft auth uses OAuth authorization code with PKCE. Refresh credentials are stored in Keychain, and Lazyest Work gets the Graph user ID from `/me`.
- Google product icons are downloaded locally and ignored by Git.

## Troubleshooting

- **Google unavailable in this build**: install an official release or rebuild with the publisher Client ID.
- **Google sign-in opens and closes**: install the latest build and click **Connect Google** again.
- **Meeting alerts do not appear**: allow Lazyest Work in **System Settings -> Notifications**, then enable Meeting alerts again.
- **Need to verify alerts**: open **Settings -> Calendar & Mail -> Test alert** and click **Send**.
- **Do Not Disturb during meetings asks for approval**: click **Approve**, then click **Add Shortcut** once in macOS. Lazyest Work turns the setting on automatically after approval.
- **Microsoft sign-in is denied**: retry and allow profile and Teams presence access. Lazyest Work shows the Entra error returned by the organization instead of a generic CLI failure.
- **Teams status asks for organization approval**: your Microsoft organization controls app registration and delegated Graph consent. Lazyest Work creates a user-owned app without administrator consent when the tenant allows it, but it cannot override a tenant denial.
- **Teams Busy does not appear immediately**: the settings card reports the Graph result first. The Teams app can lag behind the service state for a few minutes.
- **Teams call block stays off after enabling**: open **Settings -> Teams call block**, turn it on again, and enable **Lazyest Work** in macOS System Settings if macOS asks.
- **Teams call block misses an icon-only Teams button**: Teams must expose that control through macOS Accessibility with a call label. Lazyest Work avoids coordinate-only guesses because they can block unrelated buttons.
- **Old behavior after updating**: rerun the installer command; it restarts the menu app after replacing it.
- **Need icons only**:

```bash
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms --no-install
```

## Development Checks

Rust is only needed for the Rust workspace checks.

```bash
cargo test
cargo fmt --check
cargo clippy --all-targets -- -D warnings
swift build --package-path macos/LazyestWork
scripts/test-lazyest-work-core.sh
bash -n scripts/package-macos-release.sh
```
