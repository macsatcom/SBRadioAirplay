#!/bin/sh
# Host integration: receiver --state-dir files follow a real session, and the
# HTTP audio server is loopback-only unless --http-lan.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RECEIVER=${RECEIVER:-$ROOT/build/out/host/airplay-receiver}
IP=${IP:-$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')}
WORK="$ROOT/build/work/state-test"
STATE="$WORK/state"
NAME=StateTest$$
rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$WORK/receiver.log"
SENDER=$(sh "$ROOT/tests/raop_send.sh")
FIX="$WORK/sine.raw"
python3 "$ROOT/tests/make_fixture.py" "$FIX" 4

cleanup() { kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; }
fail() { echo "FAIL $*"; tail -5 "$LOG"; ls -la "$STATE" 2>/dev/null; cleanup; exit 1; }
wait_file() { # $1 file, $2 expected content (grep -x)
    i=0
    until [ -f "$1" ] && grep -qx "$2" "$1"; do
        i=$((i + 1)); [ $i -gt 100 ] && fail "$(basename "$1") never became '$2' (is: $(cat "$1" 2>/dev/null))"; sleep 0.1
    done
}

"$RECEIVER" --name "$NAME" --ip "$IP" --state-dir "$STATE" > "$LOG" 2>&1 &
PID=$!
wait_file "$STATE/state" stopped
echo "ok   initial state stopped"
port=$(python3 "$ROOT/tests/mdns_browse.py" 5 | grep "@$NAME\._raop\._tcp" | cut -f2)
[ -n "$port" ] || fail "not found via mDNS"

"$SENDER" -a -p "$port" -e "$IP" "$FIX" > "$WORK/sender.log" 2>&1 & S=$!
wait_file "$STATE/state" playing
read -r gen hport < "$STATE/stream" || fail "no stream file"
[ "$gen" = 1 ] || fail "first generation is $gen"
grep -q "url=http://127.0.0.1:$hport/stream" "$LOG" || fail "STREAM url not loopback"
[ -f "$STATE/volume" ] && grep -qE '^[01]\.[0-9]{3}$' "$STATE/volume" || fail "volume file"
echo "ok   playing: generation 1, port $hport, volume $(cat "$STATE/volume")"

curl -s -m 2 "http://$IP:$hport/stream" -o /dev/null; rc=$?
[ $rc = 7 ] || fail "HTTP reachable on LAN IP (curl rc $rc)"
curl -s -m 2 "http://127.0.0.1:$hport/stream" -o "$WORK/cap.pcm"
[ -s "$WORK/cap.pcm" ] || fail "no audio on loopback"
echo "ok   audio on loopback only"

sleep 3; kill -9 $S; wait $S 2>/dev/null
wait_file "$STATE/state" stopped
echo "ok   stopped after sender vanished"

"$SENDER" -a -p "$port" -e "$IP" "$FIX" > "$WORK/sender.log" 2>&1 & S=$!
wait_file "$STATE/state" playing
read -r gen hport < "$STATE/stream"
[ "$gen" = 2 ] || fail "second generation is $gen"
echo "ok   second session: generation 2"
kill -9 $S; wait $S 2>/dev/null
[ -z "$(ls "$STATE" | grep '\.tmp$')" ] || fail "leftover .tmp files"
cleanup
echo "ok   state test passed"
