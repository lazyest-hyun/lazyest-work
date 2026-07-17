# Lazyest Work

Native macOS menu bar app for Google Workspace shortcuts, read-only Google Calendar, meeting alerts, and an optional Gmail unread badge.

![Lazyest Work setup card](docs/screenshots/menu-setup-card.png)

## What It Does

- Opens Gmail, Calendar, Meet, Chat, Drive, Docs, Sheets, Slides, and custom Google services from the menu bar.
- Shows your upcoming Google Calendar events and the current or next meeting in the menu bar.
- Sends optional macOS desktop alerts before meetings.
- Can turn on Do Not Disturb during accepted meetings.
- Can ask for confirmation before Microsoft Teams outgoing call buttons and block Control-scroll zoom in Teams.
- Can set Microsoft Teams status to Busy during accepted meetings through Microsoft 365 CLI when Microsoft Graph consent is available.
- Shows an optional Gmail Inbox unread badge, capped as `99+`.
- Stores Google sign-in in Keychain. Teams status uses Microsoft 365 CLI's stored grant unless a native Microsoft client ID is configured.

## Install

This repository distributes source, not a prebuilt release. An AI agent can build the current source, install it into `/Applications`, launch it, and remove the temporary checkout with one command:

```sh
(workdir="$(mktemp -d)" && trap 'rm -rf "$workdir"' EXIT && git clone --depth 1 --quiet https://github.com/hyunn515/lazyest-work.git "$workdir" && "$workdir/scripts/install-macos-app.sh")
```

The bundle identifier remains stable across the rename so an existing installation keeps its macOS permissions and Keychain session. Fresh source builds need publisher Google OAuth configuration before Google sign-in is available.

For local development:

```bash
git clone https://github.com/hyunn515/lazyest-work.git
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
- **Teams status**: optional Microsoft Graph integration through Microsoft 365 CLI.
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
2. Turn on **Teams status**.
3. If Microsoft is not connected, approve Microsoft CLI browser sign-in once.
4. The Microsoft 365 CLI stores the Microsoft grant and reuses it until it expires or is revoked.

When you connect or enable Teams status, Lazyest Work uses Microsoft 365 CLI with Microsoft's first-party **Microsoft Graph Command Line Tools** app ID (`14d82eec-204b-4c2f-b7e8-296a70dab67e`) if the app bundle has no native Microsoft client ID. If the `m365` command is not installed, Lazyest Work falls back to `npx -p @pnp/cli-microsoft365 m365`, so Node.js/npm must be available.

For a managed build, pass `GWS_MICROSOFT_CLIENT_ID` and optionally `GWS_MICROSOFT_TENANT_ID` only after the organization has approved that Microsoft Graph client. The installer does not copy stale Microsoft client IDs from older app bundles.

The settings card shows whether Lazyest Work set Teams preferred status to Busy, kept an existing Lazyest Work Busy value, cleared it, or is waiting for an active accepted meeting. Teams can take a few minutes to show a successful Microsoft Graph presence update.

Lazyest Work calls Microsoft Graph `setUserPreferredPresence` while a qualifying meeting is active and `clearUserPreferredPresence` when the meeting ends, the setting is turned off, or Microsoft is signed out.

### Teams Call Block

Teams call block is local-only and does not require Microsoft sign-in.

1. Open **Settings -> Teams call block**.
2. Turn on **Teams call block**.
3. If macOS permission is missing, turning the toggle on opens System Settings. Enable **Lazyest Work** there, then Lazyest Work turns the feature on automatically.

Lazyest Work blocks only Teams elements whose accessibility role and label identify an outgoing call action, such as **Meet now**, **Audio call**, **Video call**, **음성 통화**, or **영상 통화**. It does not intentionally block dropdown buttons, hang-up buttons, chat/profile buttons, or Teams status sync.

## Updating

Public builds update from GitHub Releases. Source builds can update manually:

```bash
git pull
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

The installer closes any running `LazyestWork` process, replaces `/Applications/Lazyest Work.app`, removes an older `~/Applications/Lazyest Work.app` copy when present, and opens the new version.

## Privacy and Permissions

- Calendar access uses `https://www.googleapis.com/auth/calendar.events.readonly`.
- The Gmail badge uses the non-sensitive `https://www.googleapis.com/auth/gmail.labels` scope only when enabled. Google defines it as label read/write access; Lazyest Work only performs a read of the Inbox `messagesUnread` field because Google offers no count-only scope.
- Teams status uses Microsoft Graph delegated presence access through Microsoft 365 CLI unless a native Microsoft client ID is explicitly configured.
- Teams call block uses macOS Accessibility and event monitoring permissions only when enabled. It does not require Microsoft Graph or Teams sign-in.
- Lazyest Work does not read Gmail sender, subject, body, attachments, or message IDs.
- Lazyest Work does not send desktop mail alerts.
- Do Not Disturb during meetings uses macOS Do Not Disturb; your Focus settings decide which apps or people are allowed through.
- Lazyest Work does not turn off a Do Not Disturb state that was already active before it touched it.
- Google auth is handled by Google Sign-In and Keychain.
- Microsoft auth for Teams status uses Microsoft 365 CLI unless a native Microsoft client ID is explicitly configured. Lazyest Work gets the Graph user ID from `/me`.
- Google product icons are downloaded locally and ignored by Git.

## Troubleshooting

- **Google unavailable in this build**: install an official release or rebuild with the publisher Client ID.
- **Google sign-in opens and closes**: install the latest build and click **Connect Google** again.
- **Meeting alerts do not appear**: allow Lazyest Work in **System Settings -> Notifications**, then enable Meeting alerts again.
- **Need to verify alerts**: open **Settings -> Calendar & Mail -> Test alert** and click **Send**.
- **Do Not Disturb during meetings asks for approval**: click **Approve**, then click **Add Shortcut** once in macOS. Lazyest Work turns the setting on automatically after approval.
- **Teams status backend is missing**: install Node.js/npm or the `m365` CLI, then turn on **Settings -> Teams status** again.
- **Teams status asks for organization approval**: your Microsoft organization controls Graph presence consent. Use an approved Microsoft Graph Command Line Tools grant or leave Teams status off.
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

Teams status uses Microsoft 365 CLI with Microsoft's first-party Microsoft Graph Command Line Tools app ID when no native Microsoft client is configured.
