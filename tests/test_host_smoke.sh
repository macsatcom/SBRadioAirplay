#!/bin/sh
# Host smoke test: READY line, mDNS advertisement, verified RSA Apple-Challenge, clean SIGTERM.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RECEIVER=${RECEIVER:-$ROOT/build/out/host/airplay-receiver}
IP=${IP:-$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')}
NAME=SmokeTest$$
LOG=$(mktemp)
fail() { echo "FAIL $*"; cat "$LOG"; kill "$PID" 2>/dev/null; exit 1; }

# shellcheck disable=SC2086
$RECEIVER --name "$NAME" --ip "$IP" > "$LOG" 2>&1 &
PID=$!

i=0
until grep -q "^READY name=$NAME" "$LOG"; do
    i=$((i + 1)); [ $i -gt 50 ] && fail "no READY line within 5 s"
    sleep 0.1
done
echo "ok   READY"

line=$(python3 "$ROOT/tests/mdns_browse.py" 5 | grep "@$NAME\._raop\._tcp") || fail "not found via mDNS"
port=$(echo "$line" | cut -f2)
echo "ok   mDNS: $(echo "$line" | cut -f1) port $port"

python3 "$ROOT/tests/rtsp_challenge.py" "$IP" "$port" || fail "Apple-Challenge"
python3 "$ROOT/tests/rtsp_bad_fmtp.py" "$IP" "$port" || fail "huge ALAC frame size"
sleep 0.5
kill -0 "$PID" 2>/dev/null || fail "receiver died on huge ALAC frame size"

start=$(date +%s%N)
kill -TERM "$PID"
i=0
while kill -0 "$PID" 2>/dev/null; do
    i=$((i + 1)); [ $i -gt 20 ] && fail "still running 2 s after SIGTERM"
    sleep 0.1
done
wait "$PID"; rc=$?
[ $rc = 0 ] || fail "exit code $rc"
echo "ok   SIGTERM exit 0 in $(( ($(date +%s%N) - start) / 1000000 )) ms"
rm -f "$LOG"

# No usable IPv4 interface (only loopback): must refuse to start with a clear error.
if unshare -rn true 2>/dev/null; then
    out=$(unshare -rn sh -c "ip link set lo up; timeout 5 $RECEIVER --name NoNet" 2>&1); rc=$?
    { [ $rc = 1 ] && echo "$out" | grep -q "no usable IPv4 interface"; } \
        && echo "ok   no network: clear error, exit 1" \
        || { echo "FAIL no network: rc=$rc: $out"; exit 1; }
else
    echo "skip no-network check (unshare not permitted)"
fi
