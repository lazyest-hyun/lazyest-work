# GWS Menu

Native macOS menu bar app for Google Workspace shortcuts, read-only Google Calendar, meeting alerts, and an optional Gmail unread badge.

![GWS Menu setup card](docs/screenshots/menu-setup-card.png)

## What It Does

- Opens Gmail, Calendar, Meet, Chat, Drive, Docs, Sheets, Slides, and custom Google services from the menu bar.
- Shows your upcoming Google Calendar events and the current or next meeting in the menu bar.
- Sends optional macOS desktop alerts before meetings.
- Can turn on Do Not Disturb during accepted meetings.
- Can ask for confirmation before Microsoft Teams outgoing call buttons and block Control-scroll zoom in Teams.
- Can set Microsoft Teams status to Busy during accepted meetings through Microsoft 365 CLI when Microsoft Graph consent is available.
- Shows an optional Gmail Inbox unread badge, capped as `99+`.
- Stores Google sign-in in Keychain. Teams status uses Microsoft 365 CLI's stored grant unless a native Microsoft client ID is configured.

## Quick Start

1. Install Xcode Command Line Tools if Swift is not available:

```bash
xcode-select --install
```

2. Clone the repository and run the installer:

```bash
git clone https://github.com/hyunn515/gws-menu-app.git
cd gws-menu-app
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

This command downloads Google product icons into git-ignored local resources, builds the macOS app, installs it to `/Applications/GWSMenu.app`, and opens it.

No DMG, notarization, or paid Apple Developer account is required when you build from source.

## Connect Google

Open GWS Menu from the menu bar and click **Open Setup**.

![GWS Menu setup steps](docs/screenshots/google-setup-steps.png)

### 1. Enable APIs

In Google Cloud Console, choose or create a project, then enable:

- **Google Calendar API**: required
- **Gmail API**: optional, only for the unread badge

If Google asks for an OAuth consent screen first, choose **Internal** for a Workspace organization or **External / Testing** for personal use, then add yourself as a test user.

Calendar API should look enabled:

![Google Calendar API enabled](docs/screenshots/calendar-api-enabled.png)

### 2. Create OAuth Client

Go to **Credentials -> Create credentials -> OAuth client ID**.

Use these values:

- **Application type**: `iOS`
- **Name**: anything, for example `GWS Menu`
- **Bundle ID**: copy the Bundle ID shown in GWS Menu. The default is `io.github.gwsmenu.app`.

Google labels this as `iOS`, but it is also the correct Apple-native OAuth type for this macOS sign-in flow.
If you build with a custom `GWS_BUNDLE_ID`, use that exact value here.

![Google Cloud OAuth iOS client fields](docs/screenshots/google-cloud-oauth-ios-fields.png)

After creating it, copy only the **Client ID** ending in `.apps.googleusercontent.com`.

### 3. Save and Sign In

Paste the Client ID into GWS Menu and click **Save Setup**. GWS Menu updates the local app bundle, registers the Google callback URL, restarts, and then you can click **Sign in**.

Do not use **Web application** or **Desktop app** credentials. If Google shows a `client_secret`, it is the wrong credential type. GWS Menu does not use or store a client secret.

GWS Menu shows a small **Finish setup** card for optional features:

- **Teams call block**: asks for macOS Accessibility/event-monitoring permission when enabled. Microsoft sign-in is not needed.
- **Open at login**: adds GWS Menu to macOS Login Items.
- **Meeting alerts**: asks for macOS notification permission only when you enable it.
- **Do Not Disturb during meetings**: reuses existing approval, or shows an **Approve** button for one-time macOS approval.
- **Gmail badge**: asks for Gmail unread-count permission only when you enable it. After opening Gmail from GWS Menu, the unread count refreshes faster for two minutes.

On a first install, **Teams call block** and **Open at login** can be enabled before connecting Google. Calendar alerts and Gmail badge appear after Google Calendar is connected.

## Settings

Open Settings from the gear button in GWS Menu. Changes save automatically.

- **Calendar**: choose desktop alert timing, send a test alert, and optionally enable Do Not Disturb during meetings.
- **Teams call block**: require confirmation before supported Teams outgoing call buttons and block Control-scroll zoom inside Teams.
- **Teams status**: optional Microsoft Graph integration through Microsoft 365 CLI.
- **Mail**: enable or disable the Gmail unread badge.
- **General**: enable Open at login or open the GitHub repository.
- **Account**: sign out of Google.
- **Google setup**: reset the saved Client ID and URL scheme if you need to start over.

To customize Workspace shortcuts, click the sliders button next to the **Workspace** label on the main menu. The editor uses the same grid layout as the menu.

### Do Not Disturb During Meetings

GWS Menu can turn on macOS Do Not Disturb during accepted meetings.

1. Open **Settings -> Calendar**.
2. Turn on **Do Not Disturb during meetings**.
3. If an **Approve** button appears, click it, then click **Add Shortcut** once in macOS.
4. Return to GWS Menu. The setting turns on automatically after approval.

Only current accepted meetings with a meeting link or guests trigger Focus. Tentative, unanswered, and declined meetings only show their status color in Upcoming.
If Do Not Disturb was already on before a meeting starts, GWS Menu leaves it on after the meeting ends.

### Teams Status During Meetings

GWS Menu can set your Teams preferred presence to `Busy / Busy` during accepted Google Calendar meetings.

1. Open **Settings -> Teams status**.
2. Turn on **Teams status**.
3. If Microsoft is not connected, approve Microsoft CLI browser sign-in once.
4. The Microsoft 365 CLI stores the Microsoft grant and reuses it until it expires or is revoked.

When you connect or enable Teams status, GWS Menu uses Microsoft 365 CLI with Microsoft's first-party **Microsoft Graph Command Line Tools** app ID (`14d82eec-204b-4c2f-b7e8-296a70dab67e`) if the app bundle has no native Microsoft client ID. If the `m365` command is not installed, GWS Menu falls back to `npx -p @pnp/cli-microsoft365 m365`, so Node.js/npm must be available.

For a managed build, pass `GWS_MICROSOFT_CLIENT_ID` and optionally `GWS_MICROSOFT_TENANT_ID` only after the organization has approved that Microsoft Graph client. The installer does not copy stale Microsoft client IDs from older app bundles.

The settings card shows whether GWS Menu set Teams preferred status to Busy, kept an existing GWS Menu Busy value, cleared it, or is waiting for an active accepted meeting. Teams can take a few minutes to show a successful Microsoft Graph presence update.

GWS Menu calls Microsoft Graph `setUserPreferredPresence` while a qualifying meeting is active and `clearUserPreferredPresence` when the meeting ends, the setting is turned off, or Microsoft is signed out.

### Teams Call Block

Teams call block is local-only and does not require Microsoft sign-in.

1. Open **Settings -> Teams call block**.
2. Turn on **Teams call block**.
3. If macOS permission is missing, turning the toggle on opens System Settings. Enable **GWS Menu** there, then GWS Menu turns the feature on automatically.

GWS Menu blocks only Teams elements whose accessibility role and label identify an outgoing call action, such as **Meet now**, **Audio call**, **Video call**, **음성 통화**, or **영상 통화**. It does not intentionally block dropdown buttons, hang-up buttons, chat/profile buttons, or Teams status sync.

## Updating

Open **Settings -> General -> GitHub repository**, then update manually from the repo:

```bash
git pull
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

The installer closes any running `GWSMenu` process, replaces `/Applications/GWSMenu.app`, removes an older `~/Applications/GWSMenu.app` copy when present, and opens the new version.

## Privacy and Permissions

- Calendar access uses `https://www.googleapis.com/auth/calendar.readonly`.
- The Gmail badge uses `https://www.googleapis.com/auth/gmail.labels` only when enabled.
- Teams status uses Microsoft Graph delegated presence access through Microsoft 365 CLI unless a native Microsoft client ID is explicitly configured.
- Teams call block uses macOS Accessibility and event monitoring permissions only when enabled. It does not require Microsoft Graph or Teams sign-in.
- GWS Menu does not read Gmail sender, subject, body, attachments, or message IDs.
- GWS Menu does not send desktop mail alerts.
- Do Not Disturb during meetings uses macOS Do Not Disturb; your Focus settings decide which apps or people are allowed through.
- GWS Menu does not turn off a Do Not Disturb state that was already active before it touched it.
- Google auth is handled by Google Sign-In and Keychain.
- Microsoft auth for Teams status uses Microsoft 365 CLI unless a native Microsoft client ID is explicitly configured. GWS Menu gets the Graph user ID from `/me`.
- Google product icons are downloaded locally and ignored by Git.

## Troubleshooting

- **`client_secret` error**: delete that OAuth client and create an `iOS` OAuth client instead.
- **Sign-in opens and immediately closes**: open **Setup**, save the current Client ID once, then sign in again.
- **Meeting alerts do not appear**: allow GWS Menu in **System Settings -> Notifications**, then enable Meeting alerts again.
- **Need to verify alerts**: open **Settings -> Calendar -> Test alert** and click **Send**.
- **Do Not Disturb during meetings asks for approval**: click **Approve**, then click **Add Shortcut** once in macOS. GWS Menu turns the setting on automatically after approval.
- **Teams status backend is missing**: install Node.js/npm or the `m365` CLI, then turn on **Settings -> Teams status** again.
- **Teams status asks for organization approval**: your Microsoft organization controls Graph presence consent. Use an approved Microsoft Graph Command Line Tools grant or leave Teams status off.
- **Teams Busy does not appear immediately**: the settings card reports the Graph result first. The Teams app can lag behind the service state for a few minutes.
- **Teams call block stays off after enabling**: open **Settings -> Teams call block**, turn it on again, and enable **GWS Menu** in macOS System Settings if macOS asks.
- **Teams call block misses an icon-only Teams button**: Teams must expose that control through macOS Accessibility with a call label. GWS Menu avoids coordinate-only guesses because they can block unrelated buttons.
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
swift build --package-path macos/GWSMenuBar
```

Teams status uses Microsoft 365 CLI with Microsoft's first-party Microsoft Graph Command Line Tools app ID when no native Microsoft client is configured.
