#!/bin/sh
# Build build/MessagesDigest.app and sign it.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build.sh
#   scripts/build.sh --adhoc     # no Apple developer account
#
# Why signing matters: macOS remembers the Full Disk Access grant by the app's code
# signature. With a real identity the grant survives rebuilds. With --adhoc, every
# rebuild looks like a new app and you must toggle Full Disk Access off and on again.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/MessagesDigest.app"
BUNDLE_ID=${BUNDLE_ID:-dev.local.messages-digest}

if [ "${1:-}" = "--adhoc" ]; then
  IDENTITY="-"
  echo "build: ad-hoc signing; re-grant Full Disk Access after every rebuild" >&2
elif [ -n "${SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SIGN_IDENTITY"
else
  echo "build: set SIGN_IDENTITY or pass --adhoc. Identities on this Mac:" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 64
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
sed "s/__BUNDLE_ID__/$BUNDLE_ID/" "$ROOT/Sources/Info.plist" > "$APP/Contents/Info.plist"

swiftc -O -lsqlite3 \
  -o "$APP/Contents/MacOS/messages-digest" \
  "$ROOT/Sources/main.swift"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "build: $APP" >&2
