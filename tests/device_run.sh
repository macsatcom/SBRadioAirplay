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
    rsh 'kill $(ps | grep "[/]tmp/airplay-receiver" | awk "{print \$1}") 2>/dev/null; true'
}

case "$MODE" in
test)
    upload
    stop_remote
    RECEIVER="ssh $SSH_OPTS root@$DEV /tmp/airplay-receiver" IP="$DEV" \
        CLEANUP_CMD="ssh $SSH_OPTS root@$DEV 'kill \$(ps | grep \"[/]tmp/airplay-receiver\" | awk \"{print \\\$1}\") 2>/dev/null; true'" \
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
    rsh 'p=$(ps | grep "[/]tmp/airplay-receiver" | awk "{print \$1}" | head -1);
         [ -n "$p" ] || { echo "not running"; exit 1; }
         grep -E "VmRSS|VmSize|Threads" /proc/$p/status;
         top -b -n 1 | grep -E "airplay|^CPU|jive|squeezeplay" | head -5'
    ;;
*)
    echo "mode: test|run|measure" >&2; exit 2 ;;
esac
