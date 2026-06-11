# GWS Menu

Native macOS menu bar app for Google Workspace shortcuts, read-only Google Calendar, meeting alerts, and an optional Gmail unread badge.

![GWS Menu setup card](docs/screenshots/menu-setup-card.png)

## What It Does

- Opens Gmail, Calendar, Meet, Chat, Drive, Docs, Sheets, Slides, and custom Google services from the menu bar.
- Shows your upcoming Google Calendar events and the current or next meeting in the menu bar.
- Sends optional macOS desktop alerts before meetings.
- Can run your Do Not Disturb Focus during accepted meetings.
- Shows an optional Gmail Inbox unread badge, capped as `99+`.
- Stores Google sign-in credentials in Keychain.

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

This command downloads Google product icons into git-ignored local resources, builds the macOS app, installs it to `~/Applications/GWSMenu.app`, and opens it.

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

After sign-in, GWS Menu shows a small **Finish setup** card for optional features:

- **Meeting alerts**: asks for macOS notification permission only when you enable it.
- **Meeting Focus**: runs Do Not Disturb during accepted meetings if you create two macOS Shortcuts.
- **Gmail badge**: asks for Gmail unread-count permission only when you enable it.
- **Open at login**: adds GWS Menu to macOS Login Items.

## Settings

Open Settings from the gear button in GWS Menu. Changes save automatically.

- **Calendar**: choose desktop alert timing and optional Meeting Focus.
- **Mail**: enable or disable the Gmail unread badge.
- **General**: enable Open at login or open the GitHub repository.
- **Account**: sign out of Google.
- **Google setup**: reset the saved Client ID and URL scheme if you need to start over.

To customize Workspace shortcuts, click the sliders button next to the **Workspace** label on the main menu. The editor uses the same grid layout as the menu.

### Meeting Focus

GWS Menu uses macOS Shortcuts instead of private Focus APIs.

1. Open **Settings -> Calendar -> Focus shortcuts**.
2. Create a shortcut named `GWS Menu Focus On` with **Set Focus -> Do Not Disturb -> On**.
3. Create a shortcut named `GWS Menu Focus Off` with **Set Focus -> Do Not Disturb -> Off**.
4. Turn on **Settings -> Calendar -> Meeting Focus**.

Only current accepted meetings with a meeting link or guests trigger Focus. Tentative, unanswered, and declined meetings only show their status color in Upcoming.

## Updating

Open **Settings -> General -> GitHub repository**, then update manually from the repo:

```bash
git pull
swift scripts/sync-google-app-icons.swift --accept-google-brand-terms
```

The installer closes any running `GWSMenu` process, replaces `~/Applications/GWSMenu.app`, and opens the new version.

## Privacy and Permissions

- Calendar access uses `https://www.googleapis.com/auth/calendar.readonly`.
- The Gmail badge uses `https://www.googleapis.com/auth/gmail.labels` only when enabled.
- GWS Menu does not read Gmail sender, subject, body, or attachments.
- GWS Menu does not send desktop mail alerts.
- Meeting Focus runs your local Shortcuts; your macOS Focus settings decide which apps or people are allowed through.
- Google auth is handled by Google Sign-In and Keychain.
- Google product icons are downloaded locally and ignored by Git.

## Troubleshooting

- **`client_secret` error**: delete that OAuth client and create an `iOS` OAuth client instead.
- **Sign-in opens and immediately closes**: open **Setup**, save the current Client ID once, then sign in again.
- **Meeting alerts do not appear**: allow GWS Menu in **System Settings -> Notifications**, then enable Meeting alerts again.
- **Meeting Focus does not change Do Not Disturb**: create both Shortcuts with the exact names `GWS Menu Focus On` and `GWS Menu Focus Off`.
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
