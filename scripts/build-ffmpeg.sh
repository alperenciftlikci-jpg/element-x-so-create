#!/usr/bin/env bash
#
# Cross-compile FFmpeg n6.0 for a single Android ABI.
# Designed to run on Ubuntu (GitHub Actions ubuntu-latest) with the Android NDK
# extracted at $ANDROID_NDK_HOME.
#
# Usage: ABI=arm64-v8a API=24 build-ffmpeg.sh
#
# Output goes to $OUTPUT_DIR/$ABI/ (defaults to $PWD/output/$ABI).

set -euo pipefail

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must be set}"
: "${ABI:?ABI must be set (armeabi-v7a | arm64-v8a | x86 | x86_64)}"

API="${API:-24}"
FFMPEG_VERSION="${FFMPEG_VERSION:-n6.0}"
FFMPEG_SRC="${FFMPEG_SRC:-$PWD/ffmpeg}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/output}"
JOBS="${JOBS:-$(nproc)}"

case "$ABI" in
    armeabi-v7a)
        ARCH=arm
        CPU=armv7-a
        TARGET=armv7a-linux-androideabi
        CFLAGS_EXTRA="-mthumb -mfloat-abi=softfp"
        ;;
    arm64-v8a)
        ARCH=aarch64
        CPU=armv8-a
        TARGET=aarch64-linux-android
        CFLAGS_EXTRA=""
        ;;
    x86)
        ARCH=x86
        CPU=i686
        TARGET=i686-linux-android
        # 32-bit x86 with shared libs: FFmpeg's nasm-generated objects need text
        # relocations that lld rejects (R_386_32 against local symbols). The
        # standard workaround is to disable x86 nasm; FFmpeg still uses inline
        # C and intrinsics. Modern devices barely ship 32-bit x86 anyway.
        CFLAGS_EXTRA=""
        DISABLE_X86ASM=1
        ;;
    x86_64)
        ARCH=x86_64
        CPU=x86-64
        TARGET=x86_64-linux-android
        CFLAGS_EXTRA=""
        ;;
    *)
        echo "Unknown ABI: $ABI" >&2
        exit 1
        ;;
esac

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
CXX="$TOOLCHAIN/bin/${TARGET}${API}-clang++"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
STRIP="$TOOLCHAIN/bin/llvm-strip"
NM="$TOOLCHAIN/bin/llvm-nm"

if [ ! -x "$CC" ]; then
    echo "Compiler not found: $CC" >&2
    exit 1
fi

if [ ! -d "$FFMPEG_SRC" ]; then
    echo "FFmpeg source not at $FFMPEG_SRC; clone it first." >&2
    exit 1
fi

PREFIX="$OUTPUT_DIR/$ABI"
mkdir -p "$PREFIX"
BUILD_DIR="$PWD/build/$ABI"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$BUILD_DIR"

EXTRA_CONFIGURE_ARGS=()
if [ "${DISABLE_X86ASM:-0}" = "1" ]; then
    # 32-bit x86 + shared libs: FFmpeg's C-emitted global tables (e.g. ff_h264_cabac_tables)
    # produce R_386_32 relocations even with -fPIC, and inline asm produces the same on
    # nasm-built objects. Disabling all asm (inline + external) sidesteps both. Loses some
    # codec performance on 32-bit x86 — acceptable since that ABI is essentially emulator-only.
    EXTRA_CONFIGURE_ARGS+=(--disable-asm)
fi

# Minimal configure: H.264 + HEVC decode only, shared libs, no programs/docs/network.
# Build suffix `_own` makes our .so filenames distinct from NextLib's so they can sit
# side by side in the APK without conflict.
"$FFMPEG_SRC/configure" \
    --prefix="$PREFIX" \
    --target-os=android \
    --arch="$ARCH" \
    --cpu="$CPU" \
    --enable-cross-compile \
    --sysroot="$SYSROOT" \
    --cc="$CC" \
    --cxx="$CXX" \
    --ar="$AR" \
    --ranlib="$RANLIB" \
    --strip="$STRIP" \
    --nm="$NM" \
    --extra-cflags="-O2 -fPIC $CFLAGS_EXTRA" \
    --extra-ldflags="-Wl,-z,max-page-size=16384" \
    --build-suffix="_own" \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-doc \
    --disable-everything \
    --disable-symver \
    --disable-debug \
    --disable-network \
    --disable-avdevice \
    --disable-avformat \
    --disable-postproc \
    --disable-avfilter \
    --disable-vulkan \
    --disable-v4l2-m2m \
    --disable-cuda-llvm \
    --enable-pic \
    --enable-decoder=h264 \
    --enable-decoder=hevc \
    --enable-parser=h264 \
    --enable-parser=hevc \
    --enable-swscale \
    "${EXTRA_CONFIGURE_ARGS[@]}"

make -j"$JOBS"
make install

# Strip debug symbols to shrink final .so files; keep the result in PREFIX/lib.
find "$PREFIX/lib" -name 'lib*_own.so*' -print -exec "$STRIP" --strip-unneeded {} \;

echo "Built $ABI; output in $PREFIX/lib"
ls -la "$PREFIX/lib/"