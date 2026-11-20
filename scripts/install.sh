#!/bin/sh
# Copy the built app to a stable location and start the every-3-hours LaunchAgent.
# Full Disk Access is tied to the app at this path, so always run from here.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/build/MessagesDigest.app"
DEST="$HOME/Applications/MessagesDigest.app"
LABEL=dev.local.messages-digest
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$HOME/Library/Logs/MessagesDigest"

[ -d "$SRC" ] || { echo "install: $SRC not found; run scripts/build.sh first" >&2; exit 66; }

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$LOGDIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
echo "install: app -> $DEST" >&2

sed -e "s#__APP__#$DEST#g" -e "s#__LOGDIR__#$LOGDIR#g" -e "s#__LABEL__#$LABEL#g" \
  "$ROOT/launchd/agent.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "install: LaunchAgent -> $PLIST (runs every 3 hours)" >&2
echo "install: logs -> $LOGDIR" >&2
