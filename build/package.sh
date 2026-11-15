#!/bin/sh
# Build the installable applet ZIP: AirPlay applet files + receiver binary at
# the archive root (same layout as Spotify Connect).
# usage: package.sh [baby|fab4|all]   (run build/build-arm.sh first)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${1:-all}
if [ "$TARGET" = all ]; then sh "$0" baby; sh "$0" fab4; exit 0; fi
case "$TARGET" in baby|fab4) ;; *) echo "usage: $0 [baby|fab4|all]" >&2; exit 2 ;; esac
VERSION=$(cat "$ROOT/VERSION")
BIN="$ROOT/build/out/$TARGET/airplay-receiver"
[ -x "$BIN" ] || { echo "missing $BIN; run build/build-arm.sh $TARGET" >&2; exit 1; }

STAGE="$ROOT/build/work/package-$TARGET"
rm -rf "$STAGE"; mkdir -p "$STAGE" "$ROOT/dist"
cp "$ROOT"/applet/AirPlay/*.lua "$ROOT/applet/AirPlay/strings.txt" "$STAGE/"
cp "$BIN" "$STAGE/airplay-receiver"
chmod 644 "$STAGE"/*; chmod 755 "$STAGE/airplay-receiver"
ZIP="$ROOT/dist/AirPlay-$VERSION-$TARGET.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -q -X "$ZIP" ./*)
echo "$ZIP"
