#!/bin/sh
# Host packages for cross-compiling the AirPlay receiver for Squeezebox Radio/Touch.
# The ARM musl toolchain (Bootlin armv5-eabi--musl--stable-2020.02-2) is downloaded separately.
sudo apt update
sudo apt install -y build-essential git cmake pkg-config autoconf automake libtool \
  wget curl bzip2 xz-utils file binutils python3 qemu-user qemu-user-static
