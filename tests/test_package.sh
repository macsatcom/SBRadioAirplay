#!/bin/sh
# Verify the applet ZIP: exact file list, ARM binary for the target, all Lua
# compiles under Lua 5.1. usage: test_package.sh baby|fab4
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${1:?baby|fab4}
VERSION=$(cat "$ROOT/VERSION")
ZIP="$ROOT/dist/AirPlay-$VERSION-$TARGET.zip"
fail() { echo "FAIL $*"; exit 1; }
[ -f "$ZIP" ] || fail "missing $ZIP"

want="AirPlayApplet.lua
AirPlayMeta.lua
AirPlayNowPlaying.lua
AirPlayPlayback.lua
AirPlayService.lua
AirPlayState.lua
AirPlayWatcher.lua
airplay-receiver
strings.txt"
got=$(unzip -Z1 "$ZIP" | sort)
[ "$got" = "$(echo "$want" | sort)" ] || fail "file list:
$got"
echo "ok   $TARGET: file list"

tmp=$(mktemp -d)
unzip -q "$ZIP" -d "$tmp"
file -b "$tmp/airplay-receiver" | grep -q "ARM, EABI5.*statically linked" || fail "binary is not static ARM"
cmp -s "$tmp/airplay-receiver" "$ROOT/build/out/$TARGET/airplay-receiver" || fail "binary differs from build/out/$TARGET"
unzip -Zl "$ZIP" airplay-receiver | grep -q "^-rwxr-xr-x" || fail "binary not executable in ZIP"
echo "ok   $TARGET: static ARM binary, executable"

"$ROOT/.venv/bin/python" - "$tmp" <<'EOF' || fail "Lua does not compile"
import sys, pathlib
from lupa.lua51 import LuaRuntime
lua = LuaRuntime()
check = lua.eval("function(src, name) local f, err = loadstring(src, name); return err end")
bad = 0
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.lua")):
    err = check(p.read_text(), p.name)
    if err:
        print("  ", err); bad += 1
sys.exit(1 if bad else 0)
EOF
echo "ok   $TARGET: Lua compiles"
rm -rf "$tmp"
