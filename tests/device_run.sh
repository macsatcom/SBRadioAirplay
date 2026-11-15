#!/bin/sh
# Run airplay-receiver on a Squeezebox Radio (baby) or Touch (fab4) over SSH.
#
#   tests/device_run.sh <device-ip> <baby|fab4> test     automated stream test from this PC
#   tests/device_run.sh <device-ip> <baby|fab4> run      foreground, for testing with an iPhone
#   tests/device_run.sh <device-ip> <baby|fab4> measure  RSS / CPU of the running receiver
#
# Only /tmp on the device is written. SSH_OPTS can override the legacy
# algorithms needed by the Radio's old dropbear. Default password is usually 1234.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEV=${1:?device ip}
TARGET=${2:?baby|fab4}
MODE=${3:-test}
BIN="$ROOT/build/out/$TARGET/airplay-receiver"
NAME=${NAME:-SB AirPlay Test}
SSH_OPTS=${SSH_OPTS:--o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPath=/tmp/opencode-sbssh-%r@%h -o ControlPersist=120}
# shellcheck disable=SC2086
rsh() { ssh $SSH_OPTS "root@$DEV" "$@"; }

[ -x "$BIN" ] || { echo "missing $BIN; run build/build-arm.sh $TARGET" >&2; exit 1; }

upload() {
    # cat instead of scp: the Radio has no sftp-server.
    rsh 'cat > /tmp/airplay-receiver && chmod 755 /tmp/airplay-receiver' < "$BIN"
    rsh 'uname -r; /tmp/airplay-receiver --help >/dev/null 2>&1 && echo "binary runs"'
}

stop_remote() {
    rsh 'killall airplay-receiver 2>/dev/null; sleep 1; killall -9 airplay-receiver 2>/dev/null; true'
}

case "$MODE" in
test)
    upload
    stop_remote
    RECEIVER="ssh $SSH_OPTS root@$DEV /tmp/airplay-receiver" IP="$DEV" \
        CLEANUP_CMD="ssh $SSH_OPTS root@$DEV 'killall airplay-receiver 2>/dev/null; true' </dev/null" \
        sh "$ROOT/tests/test_host_stream.sh"
    ;;
run)
    upload
    stop_remote
    echo "Starting '$NAME' on $DEV; Ctrl-C to stop. Capture from this PC with:"
    echo "  curl -s <url from STREAM line> -o capture.wav && python3 tests/check_wav.py capture.wav"
    trap stop_remote INT TERM
    rsh "/tmp/airplay-receiver --name '$NAME' --ip $DEV --codec wav -d 3" || true
    ;;
measure)
    rsh 'p=$(pidof airplay-receiver | cut -d" " -f1);
         [ -n "$p" ] || { echo "not running"; exit 1; }
         grep -E "VmRSS|VmSize|Threads" /proc/$p/status;
         a=$(cut -d" " -f14,15 /proc/$p/stat); sleep 5; b=$(cut -d" " -f14,15 /proc/$p/stat);
         set -- $a $b; echo "CPU over 5 s: $(( ($3 + $4 - $1 - $2) * 100 / 500 ))%";
         free | sed -n 2p'
    ;;
*)
    echo "mode: test|run|measure" >&2; exit 2 ;;
esac
