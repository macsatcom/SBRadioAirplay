#!/bin/sh
# Static ARM builds of airplay-receiver for baby (Radio) and fab4 (Touch).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${1:-all}
if [ "$TARGET" = all ]; then
    sh "$0" baby
    sh "$0" fab4
    printf '{"hardware":["baby","fab4"],"target":"arm-buildroot-linux-musleabi","floatAbi":"soft"}\n' \
        > "$ROOT/build/out/native-targets.json"
    exit 0
fi
. "$ROOT/build/targets.sh"
[ "$TARGET" != host ] || { echo "use build-host.sh" >&2; exit 2; }

sh "$ROOT/build/build-wolfssl.sh" "$TARGET"
cmake -S "$ROOT" -B "$ROOT/build/$TARGET" \
    -DCMAKE_TOOLCHAIN_FILE="$ROOT/build/toolchain-arm.cmake" \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_C_FLAGS="$TARGET_CFLAGS" \
    -DWOLFSSL_PREFIX="$ROOT/build/work/$TARGET/wolfssl-prefix" >/dev/null
cmake --build "$ROOT/build/$TARGET" -j"$(nproc)" --target airplay-receiver
mkdir -p "$ROOT/build/out/$TARGET"
"$TOOLCHAIN_DIR/bin/$TARGET_TRIPLE-strip" -o "$ROOT/build/out/$TARGET/airplay-receiver" \
    "$ROOT/build/$TARGET/airplay-receiver"
echo "$TARGET: $(wc -c < "$ROOT/build/out/$TARGET/airplay-receiver") bytes"
