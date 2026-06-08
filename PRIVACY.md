# Pixel Pane Privacy Policy

_Last updated: June 4, 2026_

Pixel Pane is a local-first assistant for your Mac. This policy describes what
the app can access, what (if anything) leaves your computer, and the choices
you control. The short version: **nothing leaves your Mac unless you turn on
Cloud Mode**, and every off-device data flow below is opt-in.

## What Pixel Pane can access on your Mac

- **Screen captures** — only when you start a capture yourself (hotkey or
  menu), and only the region you drag. There is no background recording and no
  screen timeline. Captured images are processed in memory and are not saved.
- **Files and folders** — only the folders you explicitly grant. Every file
  the assistant reads is recorded in the run trace you can inspect. The
  assistant cannot change a file without showing you an approval card first.
- **System snapshots** — bounded, read-only lists of running processes and
  local listening ports, used to answer questions you ask about them.
- **Chat history** — stored only on your Mac. You can review or delete any
  chat in Settings → History.

## Local Mode (the default)

In Local Mode, everything — your questions, file contents, captures, and
answers — is processed on your Mac using models you install. Pixel Pane makes
no network requests for AI processing in Local Mode.

## Cloud Mode (explicit opt-in)

When you enable Cloud Mode in Settings, requests are processed by Pixel Pane
Cloud. For each request, the following is sent to our server and forwarded to
our model provider (Anthropic) to generate the answer:

- your question and the visible conversation in that chat;
- local context the assistant gathers for the request — such as text it reads
  from your granted files, text extracted from a capture you made, the names
  of your granted folders, and the current date/time;
- your approximate, city-level location — **only** if you have separately
  granted macOS Location access **and** enabled "Share approximate location
  with Cloud" in Settings (two explicit switches; never precise coordinates);
- an anonymous device identifier (a random ID generated on your Mac — no
  account, email, or name is collected).

Cloud Mode answers may also use **web search** run by the model provider to
fetch current public information; your searched queries derive from your
question, not from your files.

Cloud requests pass through Cloudflare (our hosting provider) and Anthropic
(the model provider). We do not sell data, build advertising profiles, or use
your content to train models. Anthropic's handling of API data is described in
their [usage policies](https://www.anthropic.com/legal/privacy).

### Limits and abuse prevention

To keep the free tier sustainable we keep short-lived counters (reset daily)
of anonymous device IDs and requesting IP addresses. These are used only for
rate limiting and are not linked to your content or identity.

## What Pixel Pane does not do

- No analytics, tracking, or telemetry in the app.
- No accounts; nothing identifies you personally.
- No screenshots stored, in any mode.
- No background screen or file monitoring.
- No data leaves your Mac in Local Mode.

## Your controls

- Switch between Local and Cloud Mode at any time in Settings.
- Add or remove folder grants at any time in Settings → Files.
- Revoke Location access in System Settings, or turn off cloud location
  sharing in Settings.
- Delete any or all chat history in Settings → History.

## Contact

Questions about this policy: snehithn5@gmail.com

## Changes

We will update this document when data practices change and note the date at
the top.
