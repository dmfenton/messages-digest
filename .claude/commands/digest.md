---
description: Summarize my recent text messages (default last 3 hours)
argument-hint: "[hours]"
allowed-tools: Bash(scripts/refresh.sh:*), Read
---

Make a digest of my recent Apple Messages.

1. Run `scripts/refresh.sh $ARGUMENTS` (empty means 3 hours). It prints the snapshot path.
2. Read that JSON file.
3. If `status` is not `ok`, stop and tell me what to fix:
   - `needs_full_disk_access`: System Settings > Privacy & Security > Full Disk Access,
     add `~/Applications/MessagesDigest.app`, toggle it on, then rerun.
   - anything else: show `status` and `detail`.
4. Otherwise write a short digest:
   - **Needs a reply**: incoming messages that ask me something or expect an answer and
     that I have not answered later in the same chat (`from_me: true` after it).
   - **Plans and dates**: anything with a time, place, or commitment.
   - **FYI**: everything else, one line per conversation.
   Group by conversation using `chats[].title` (group name or member names). Name senders
   with `sender_name`, falling back to `sender`. If `contacts` is not `authorized`, mention
   once that names need the app's Contacts permission.
   Times in my local zone. Skip empty sections. Say "Nothing new" if there are no messages.

Rules: read only. Never send, reply to, or draft messages. Do not copy message text into
files, commits, or anywhere outside this conversation.
