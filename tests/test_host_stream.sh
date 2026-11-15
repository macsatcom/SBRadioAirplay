#!/bin/sh
# End-to-end host test: libraop's raop_play sends a 1 kHz tone to our receiver,
# we capture the HTTP audio stream and verify it.
# RECEIVER and IP may be overridden; tests/device_run.sh runs the receiver on a
# Radio over SSH and sets CLEANUP_CMD to stop it remotely.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RECEIVER=${RECEIVER:-$ROOT/build/out/host/airplay-receiver}
IP=${IP:-$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')}
WORK="$ROOT/build/work/stream-test"
NAME=StreamTest$$
mkdir -p "$WORK"
LOG="$WORK/receiver.log"
SENDER=$(sh "$ROOT/tests/raop_send.sh")
FIX="$WORK/sine1k-6s.raw"
[ -f "$FIX" ] || python3 "$ROOT/tests/make_fixture.py" "$FIX" 6

cleanup() { [ -n "${CLEANUP_CMD:-}" ] && sh -c "$CLEANUP_CMD"; kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; }
fail() { echo "FAIL $*"; tail -20 "$LOG"; cleanup; exit 1; }

# shellcheck disable=SC2086
$RECEIVER --name "$NAME" --ip "$IP" --codec wav > "$LOG" 2>&1 &
PID=$!
i=0
until grep -q "^READY" "$LOG"; do
    i=$((i + 1)); [ $i -gt 100 ] && fail "no READY"; sleep 0.1
done
port=$(python3 "$ROOT/tests/mdns_browse.py" 5 | grep "@$NAME\._raop\._tcp" | cut -f2)
[ -n "$port" ] || fail "receiver not found via mDNS"

wait_stream() { # $1 = expected count of STREAM lines
    i=0
    until [ "$(grep -c '^STREAM' "$LOG")" -ge "$1" ]; do
        i=$((i + 1)); [ $i -gt 100 ] && fail "no STREAM line #$1"; sleep 0.1
    done
    grep '^STREAM' "$LOG" | sed -n "$1p" | sed 's/.* url=//'
}

send() { "$SENDER" -a -p "$port" -e "$IP" "$FIX" > "$WORK/sender.log" 2>&1 & SPID=$!; }
# raop_play hangs in its own disconnect (joins a thread that never exits), so
# after the 6 s fixture plus 1 s latency we kill it hard. That is also the
# "sender vanished without TEARDOWN" case: the receiver must report STOP.
finish_send() { # $1 = expected count of STOP lines
    sleep 8
    kill -9 "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
    i=0
    until [ "$(grep -c '^STOP' "$LOG")" -ge "$1" ]; do
        i=$((i + 1)); [ $i -gt 30 ] && fail "no STOP #$1 within 3 s of sender vanishing"; sleep 0.1
    done
}

# 0. a sender using uncompressed PCM (unsupported) must not kill the receiver
timeout 5 "$SENDER" -p "$port" -e "$IP" "$FIX" > "$WORK/sender-pcm.log" 2>&1
sleep 0.5
kill -0 "$PID" 2>/dev/null || fail "receiver died on PCM-only sender"
echo "ok   survives unsupported PCM sender"

# 1. basic stream
send
url=$(wait_stream 1)
curl -s -m 9 "$url" -o "$WORK/capture1.wav" & CPID=$!
finish_send 1; wait "$CPID"
python3 "$ROOT/tests/check_wav.py" "$WORK/capture1.wav" || fail "capture 1"

# 2. second session after the first finished (reconnect)
send
url=$(wait_stream 2)
curl -s -m 9 "$url" -o "$WORK/capture2.wav" & CPID=$!
finish_send 2; wait "$CPID"
python3 "$ROOT/tests/check_wav.py" "$WORK/capture2.wav" || fail "capture 2 (reconnect)"

# 3. late HTTP client, dropped and reconnected mid-stream
send
url=$(wait_stream 3)
sleep 2
curl -s -m 1 "$url" -o "$WORK/capture3a.wav"
curl -s -m 3 "$url" -o "$WORK/capture3b.wav"
finish_send 3
kill -0 "$PID" 2>/dev/null || fail "receiver died after HTTP client reconnect"
[ -s "$WORK/capture3b.wav" ] || fail "no audio after HTTP client reconnect"
echo "ok   late/reconnected HTTP client: $(wc -c < "$WORK/capture3b.wav") bytes"

cleanup
echo "ok   stream test passed"
