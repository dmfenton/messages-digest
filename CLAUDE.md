# messages-digest

A toy that teaches one pattern: **give a sensitive permission to one tiny app, and let
everything else (including Claude) read that app's output file.**

Reading Apple Messages requires Full Disk Access (FDA). Messages' AppleScript dictionary
can list chats and send texts but cannot read message text, so "Automation" permission
is not enough. Rather than granting FDA to Terminal or Claude (which would let them read
everything on disk), this repo builds `MessagesDigest.app`, which gets FDA and does
exactly one read-only thing. The app also holds its own Contacts permission, so the
snapshot carries names instead of bare phone numbers.

## How it fits together

```text
~/Library/Messages/chat.db
        |  read-only SQLite (needs FDA, granted ONLY to the app)
        v
~/Applications/MessagesDigest.app   <- launchd every 3h, or scripts/refresh.sh on demand
        |  writes atomically, mode 0600
        v
~/Library/Application Support/MessagesDigest/latest.json
        |  plain file read (no special permission)
        v
Claude: /digest  ->  "needs a reply / plans / FYI" summary
```

| Piece | File | Job |
|---|---|---|
| Exporter | `Sources/main.swift` | Query last N hours, decode text, list chat members, write JSON with a `status` field |
| Names | `Sources/Contacts.swift` | Map phone/email to contact names (app's own Contacts grant) |
| Entitlement | `Sources/MessagesDigest.entitlements` | Hardened runtime needs it to use Contacts |
| Build | `scripts/build.sh` | Compile, wrap as `.app`, codesign |
| Install | `scripts/install.sh` | Copy to `~/Applications`, load the LaunchAgent |
| On-demand run | `scripts/refresh.sh` | `open` the app so macOS checks the app's grant, not the caller's |
| Schedule | `launchd/agent.plist` | Every 3 hours + at login |
| Summary | `.claude/commands/digest.md` | The `/digest` slash command |

## Setup (first time)

1. Build. With an Apple Developer ID (grant survives rebuilds):
   `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build.sh`
   Without one: `scripts/build.sh --adhoc` (re-toggle FDA after each rebuild).
   `security find-identity -v -p codesigning` lists identities.
2. `scripts/install.sh`
3. System Settings > Privacy & Security > Full Disk Access > `+` >
   `~/Applications/MessagesDigest.app` (Cmd-Shift-G to type the path). Toggle on.
4. The first run asks for Contacts access for MessagesDigest; allow it for names (optional).
5. `scripts/refresh.sh` then check `status` in the printed file is `ok`.
6. In Claude Code in this folder: `/digest` (or `/digest 24` for a day).

## Running it every few hours with Claude

The LaunchAgent keeps the snapshot fresh. To get a summary on a schedule, create a
scheduled task in the Claude desktop app (Code tab, folder = this repo, prompt `/digest`,
every 3 hours), or ask Claude to "make a scheduled task that runs /digest every 3 hours".

## Things to know when changing this

- **Who TCC checks.** macOS checks the "responsible process". A binary started from a
  shell inherits the shell's (denied) permission. `open` or launchd make the app its own
  responsible process. That is why `refresh.sh` uses `open -n -W -g`.
- **Dates.** `message.date` is nanoseconds since 2001-01-01 UTC.
- **Text.** Recent macOS often leaves `message.text` NULL and stores an archived
  `NSAttributedString` in `attributedBody`; `decodeAttributedBody` handles it.
- **Filtered out.** Tapbacks (`associated_message_type != 0`) and system items
  (`item_type != 0`).
- **Names.** Handles match contacts on the last 10 phone digits or the lowercased email.
  Denied Contacts access is not an error: `contacts` says why and names are omitted.
- **Snapshot shape.** `chats[]` has `title`, `is_group`, `members[]` (handle + name),
  `received`, `sent`; `messages[]` has `sender`, `sender_name`, `chat`, `text`.
- **Errors are data.** A failed run still writes `latest.json` with `status` and `detail`,
  so the reader always knows why there are no messages.

## Privacy rules

- Never commit `latest.json` or any message content (`.gitignore` blocks `*.json`).
- The app must stay read-only: no writes to chat.db, no network, no sending.
- Uninstall with `scripts/uninstall.sh`, then remove the app from the FDA list.

## Ideas to extend

- A `--since-last-run` mode that stores the last exported message date.
- WhatsApp: same pattern against its `ChatStorage.sqlite`.
