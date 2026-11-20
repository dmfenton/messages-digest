# messages-digest

Have Claude summarize your recent iMessages every few hours, without giving Claude
(or your terminal) Full Disk Access.

A ~200-line Swift app gets Full Disk Access, reads the last few hours of
`~/Library/Messages/chat.db` read-only, looks up names with its own Contacts permission,
and writes a private JSON file. Claude reads
that file with the `/digest` command.

Requires macOS 13+, Xcode command line tools, and Claude Code.

```sh
scripts/build.sh --adhoc      # or SIGN_IDENTITY="Developer ID Application: ..." scripts/build.sh
scripts/install.sh
# System Settings > Privacy & Security > Full Disk Access > + ~/Applications/MessagesDigest.app
scripts/refresh.sh            # prints the snapshot path; check "status": "ok"
claude                        # then type /digest
```

See [CLAUDE.md](CLAUDE.md) for how it works and how to extend it.
