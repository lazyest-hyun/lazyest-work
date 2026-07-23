# Lazyest Work — Google OAuth verification package

Use this document as the factual source for the Google Cloud Verification Center submission. Do not submit a scope, claim, or video step that differs from the released app.

## Requested scopes

| Scope | Classification | Actual use |
| --- | --- | --- |
| `https://www.googleapis.com/auth/calendar.events.readonly` | Sensitive | Reads upcoming events from the user's primary Google Calendar. |
| `https://www.googleapis.com/auth/gmail.labels` | Non-sensitive | Reads only the Inbox label's `messagesUnread` field. |

OpenID Connect sign-in scopes (`openid`, `email`, and `profile`) are used only to identify the signed-in Google account.

## Sensitive-scope justification (submit in English)

> Lazyest Work is a macOS menu bar productivity application. When a user explicitly enables Google Calendar, the app uses `https://www.googleapis.com/auth/calendar.events.readonly` to read events from the user's primary calendar in a rolling seven-day window. It displays the next upcoming meetings in the menu bar and uses event start/end times, title, description, location, meeting link, event status/type, organizer, and attendee response information to provide local meeting reminders and meeting-assistance controls. The app never creates, modifies, deletes, or shares calendar events. Calendar data is processed locally on the user's Mac; Google access tokens are stored in macOS Keychain and the app does not sell, use for advertising, or transfer Google user data to third parties. `calendar.events.readonly` is the narrowest Calendar scope that permits reading the event details needed for those user-facing features.

Public disclosure: https://lazyest.com/google-data-use.html

## Gmail note (do not describe as sensitive)

> The non-sensitive `https://www.googleapis.com/auth/gmail.labels` scope is requested only when the user enables the Gmail unread badge. Lazyest Work sends `GET /gmail/v1/users/me/labels/INBOX?fields=messagesUnread` and uses only the returned unread-count value. It does not request or read Gmail sender, subject, body, attachments, or message IDs.

## Demonstration video checklist

Google requires an unlisted YouTube demonstration that shows the end-to-end OAuth grant and the in-app use of every sensitive or restricted scope. Record with a dedicated test Google account and test calendar; do not expose a real user's meetings, email addresses, meeting links, tokens, or private notifications.

1. Start with the released Lazyest Work app and show the app name and version.
2. Open the Google connection setting and show that Calendar and Gmail features are opt-in.
3. Start Google sign-in and show the complete OAuth consent screen in English. The visible app name/logo and requested scope must match the Cloud project submission.
4. Grant the Calendar permission with the test account.
5. Return to Lazyest Work and show a test calendar event appearing in the menu bar or upcoming-meeting view.
6. Open the relevant meeting-assistance view to show how the displayed event details support the feature. Do not use a real meeting or personal calendar data.
7. If Gmail unread badge is enabled, show that the app displays only an unread count—not email content.
8. Show the disconnect/revoke path, if available, and end on the normal app interface.

### Recording script (2–3 minutes)

| Time | Capture | Narration / evidence |
| --- | --- | --- |
| 0:00–0:15 | App name and version, then Google connection settings | “This is Lazyest Work for macOS. Google Calendar and Gmail are optional features.” |
| 0:15–0:45 | Turn on Calendar and begin sign-in | Show the real OAuth consent screen, app name, requested Calendar scope, privacy-policy and terms links. |
| 0:45–1:20 | Approve using a dedicated test account with a fabricated test meeting | Explain that the app reads a rolling seven-day primary-calendar window for the menu bar, local reminders, and meeting assistance; it never writes Calendar data. |
| 1:20–1:50 | Return to the actual app and menu-bar/upcoming-meeting view | Show only the fabricated test event and how it drives the local meeting reminder or assistance control. |
| 1:50–2:10 | Enable the Gmail badge | Show the numerical unread badge only; do not display any mail list, sender, subject, body, attachment, or message ID. |
| 2:10–2:30 | Disconnect / revoke | Show that the user can remove the connection. |

Before upload, verify that the video is set to **Unlisted** in YouTube Studio and that no passwords, OAuth codes, access tokens, private calendar data, or unrelated accounts are visible.

## Video readiness gate

The video must be recorded from the actual released app and real OAuth flow. A scripted, mocked, or edited substitute should not be submitted. Record and upload it only after the app can launch reliably and the branding status is published.
