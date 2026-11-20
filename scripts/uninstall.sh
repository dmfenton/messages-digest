#!/bin/sh
# Stop the LaunchAgent and remove the app and its snapshot.
set -eu
LABEL=dev.local.messages-digest
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/MessagesDigest.app" "$HOME/Library/Application Support/MessagesDigest"
echo "uninstall: done. Also remove MessagesDigest from System Settings > Privacy & Security > Full Disk Access." >&2
