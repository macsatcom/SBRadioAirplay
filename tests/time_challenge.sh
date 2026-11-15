#!/bin/sh
# Time N Apple-Challenge round trips (one RSA-2048 private op each) against a receiver.
# usage: time_challenge.sh <ip> <name> [N]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IP=$1; NAME=$2; N=${3:-5}
for i in $(seq 10); do port=$(python3 "$ROOT/tests/mdns_browse.py" 5 | grep "@$NAME\._raop" | cut -f2); [ -n "$port" ] && break; done
[ -n "$port" ] || { echo "FAIL $NAME not found"; exit 1; }
start=$(date +%s%N)
for i in $(seq "$N"); do python3 "$ROOT/tests/rtsp_challenge.py" "$IP" "$port" >/dev/null || { echo "FAIL challenge"; exit 1; }; done
echo "ok   $(( ($(date +%s%N) - start) / 1000000 / N )) ms per Apple-Challenge"
