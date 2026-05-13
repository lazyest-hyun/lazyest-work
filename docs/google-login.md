# Google Login Setup

GWS Menu uses Google Sign-In. Calendar sign-in requests:

```text
https://www.googleapis.com/auth/calendar.readonly
```

The Gmail unread badge is optional. If enabled in Settings, GWS Menu also requests:

```text
https://www.googleapis.com/auth/gmail.labels
```

That optional scope is used only for Inbox unread counts.

## Steps

1. Enable **Google Calendar API** in Google Cloud.
2. Optional: enable **Gmail API** if you want the Gmail unread badge.
3. Create an OAuth client.
4. Choose application type **iOS**. Google uses this for Apple native apps, including macOS apps.
5. Use the Bundle ID shown in GWS Menu. The default is `io.github.gwsmenu.app`.
6. Copy only the generated **Client ID** ending in `.apps.googleusercontent.com`.
7. Paste it into GWS Menu, click **Save Setup**, then sign in.

Do not use **Web application** credentials. If Google shows a `client_secret`, it is the wrong type.

## Notifications

- **Settings -> Calendar -> Desktop alerts** uses macOS notifications at the selected meeting alert time.
- **Settings -> Mail -> Inbox unread badge** shows the unread count on the menu bar icon and Gmail tile, capped as `99+`.
- The Gmail badge does not read sender, subject, body, or attachments, and it does not send desktop mail alerts.

## Reset

- **Sign Out** retries the same Google setup.
- **Settings -> Google setup -> Reset** removes the saved Client ID and URL scheme from the current app bundle.
