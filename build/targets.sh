# Sourced by build scripts: sets TARGET_CC, TARGET_CFLAGS, TARGET_TRIPLE for $TARGET.
TOOLCHAIN_DIR="$ROOT/build/toolchains/armv5-eabi--musl--stable-2020.02-2"
TARGET_TRIPLE=arm-buildroot-linux-musleabi
case "$TARGET" in
    host)
        TARGET_CC=${CC:-cc}
        TARGET_CFLAGS="-O2 -g"
        ;;
    baby)
        TARGET_CC="$TOOLCHAIN_DIR/bin/$TARGET_TRIPLE-gcc"
        TARGET_CFLAGS="-Os -marm -march=armv5te -mtune=arm926ej-s -mfloat-abi=soft -ffunction-sections -fdata-sections"
        ;;
    fab4)
        TARGET_CC="$TOOLCHAIN_DIR/bin/$TARGET_TRIPLE-gcc"
        TARGET_CFLAGS="-Os -marm -march=armv6 -mtune=arm1136jf-s -mfloat-abi=soft -ffunction-sections -fdata-sections"
        ;;
    *)
        echo "unknown target: $TARGET (host|baby|fab4)" >&2
        exit 2
        ;;
esac
