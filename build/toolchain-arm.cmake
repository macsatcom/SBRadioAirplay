# CMake toolchain for the Bootlin ARMv5 musl toolchain. Per-target CPU flags
# come from build/targets.sh via CMAKE_C_FLAGS.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(TOOLCHAIN_DIR ${CMAKE_CURRENT_LIST_DIR}/toolchains/armv5-eabi--musl--stable-2020.02-2)
set(CMAKE_C_COMPILER ${TOOLCHAIN_DIR}/bin/arm-buildroot-linux-musleabi-gcc)
set(CMAKE_FIND_ROOT_PATH ${TOOLCHAIN_DIR}/arm-buildroot-linux-musleabi/sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static -no-pie -Wl,--gc-sections")
