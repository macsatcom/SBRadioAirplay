#!/bin/sh
# Verify a cross-built airplay-receiver: static ARM EABI5 soft-float, no
# interpreter/dynamic section, runs under qemu, no syscalls missing on 2.6.26.
# usage: test_arm_binary.sh baby|fab4
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${1:?baby|fab4}
BIN="$ROOT/build/out/$TARGET/airplay-receiver"
case "$TARGET" in baby) CPU=arm926 ;; fab4) CPU=arm1136 ;; *) echo "bad target"; exit 2 ;; esac
NM="$ROOT/build/toolchains/armv5-eabi--musl--stable-2020.02-2/bin/arm-buildroot-linux-musleabi-nm"
fail=0
ok() { echo "ok   $TARGET: $*"; }
bad() { echo "FAIL $TARGET: $*"; fail=1; }

[ -x "$BIN" ] || { bad "missing $BIN"; exit 1; }
f=$(file -b "$BIN")
echo "$f" | grep -q "ELF 32-bit LSB executable, ARM, EABI5" && ok "ARM EABI5" || bad "file: $f"
echo "$f" | grep -q "statically linked" && ok "static" || bad "not static: $f"
readelf -l "$BIN" | grep -q INTERP && bad "has INTERP" || ok "no INTERP"
readelf -d "$BIN" 2>&1 | grep -q "no dynamic section" && ok "no dynamic section" || bad "has dynamic section"
readelf -A "$BIN" | grep -q "Tag_ABI_VFP_args: VFP registers" && bad "hard-float ABI" || ok "soft-float ABI"

# Linux 2.6.26 lacks these; they are only allowed when routed through the shim.
syms=$("$NM" "$ROOT/build/$TARGET/airplay-receiver" 2>/dev/null || true)
for s in epoll_create1 eventfd accept4 pipe2 dup3 inotify_init1 signalfd getrandom; do
    if echo "$syms" | grep -qw "$s" && ! echo "$syms" | grep -qw "__wrap_$s"; then
        bad "uses $s without linux26 shim"
    fi
done
[ $fail = 0 ] && ok "no unshimmed 2.6.26-missing syscalls"

qemu-arm -cpu "$CPU" "$BIN" --help >/dev/null 2>&1 && ok "qemu -cpu $CPU --help" || bad "qemu run failed"
exit $fail
