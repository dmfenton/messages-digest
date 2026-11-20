#!/bin/sh
# Export the last N hours right now (default 3) and print the snapshot path.
#
# Uses `open` on purpose: the app then runs as its own process, so macOS checks the
# APP's Full Disk Access, not your terminal's or Claude's. Running the binary directly
# from a shell would be denied (the shell is the "responsible" process).
set -eu

HOURS=${1:-3}
APP="$HOME/Applications/MessagesDigest.app"
OUT="$HOME/Library/Application Support/MessagesDigest/latest.json"
TIMEOUT_SECONDS=30

[ -d "$APP" ] || { echo "refresh: $APP not found; run scripts/build.sh and scripts/install.sh" >&2; exit 66; }

before=$(stat -f %Fm "$OUT" 2>/dev/null || echo 0)
# `open -W` can't wait on an app this quick, so wait for the file to change instead.
open -n -g "$APP" --args --hours "$HOURS"

waited=0
while [ "$(stat -f %Fm "$OUT" 2>/dev/null || echo 0)" = "$before" ]; do
  if [ "$waited" -ge $((TIMEOUT_SECONDS * 10)) ]; then
    echo "refresh: $OUT was not updated within ${TIMEOUT_SECONDS}s; see ~/Library/Logs/MessagesDigest" >&2
    exit 75
  fi
  /bin/sleep 0.1
  waited=$((waited + 1))
done
echo "$OUT"
