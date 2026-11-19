#!/bin/bash
# build_ffmpeg6_macos_arm64.sh <ffmpeg-6.1.6.tar.xz> <libSpinVideo.4.x.dylib> <build dir> <out dir>
#
# Builds the minimal LGPL FFmpeg 6.1.6 that Teledyne's libSpinVideo needs to load, as the ffmpeg-spinvideo payload
# of scAnt-payloads. Same components as scAnt_pro scripts/macos/setup_spinnaker_macos.sh (b62b8e5,
# lines 182-234); what differs from that script, and why:
#   MACOSX_DEPLOYMENT_TARGET=14.0   the script sets none, so its libraries get the build machine's minos
#   --prefix=/scant-ffmpeg + DESTDIR  a neutral prefix: FFmpeg embeds the configure line (and so the prefix)
#                                   in every library; the script's mktemp prefix made each build unique
#   --install-name-dir=@loader_path the libraries find each other next to themselves; the script's @rpath
#                                   relies on rpaths it adds to Teledyne's binaries, which the installer
#                                   must not touch
# Needs the Xcode Command Line Tools (clang, make, nm, otool). Run on a build Mac only.
set -euo pipefail

TARBALL="${1:?usage: $0 ffmpeg-6.1.6.tar.xz libSpinVideo.dylib build_dir out_dir}"
VIDEO="${2:?}"
BUILD="${3:?}"
OUT="${4:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python3}"

FFMPEG_VERSION="6.1.6"
FFMPEG_SHA256="d4fcb164028dd3beee5d92c0ac72e46aac6973c75ea12dc14de07bf8f407370a"
PREFIX="/scant-ffmpeg"
export MACOSX_DEPLOYMENT_TARGET=14.0
# reproducible archives/objects: no timestamps from this run
export ZERO_AR_DATE=1
export LC_ALL=C TZ=UTC

echo "$FFMPEG_SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null
mkdir -p "$BUILD" "$OUT"

configure_flags() {
    # $1: extra linker flags for the shared libraries (may be empty)
    printf '%s\n' \
        "--prefix=$PREFIX" "--install-name-dir=@loader_path" \
        --enable-shared --disable-static --disable-programs --disable-doc \
        --disable-avdevice --disable-avfilter --disable-postproc \
        --disable-network --disable-autodetect --disable-everything \
        --enable-encoder=rawvideo,mjpeg,mpeg4 --enable-muxer=avi,mp4 \
        --enable-protocol=file
    # optional experiment switch (space-separated), e.g. FFMPEG_EXTRA_CONFIGURE="--disable-debug"
    local extra_cfg
    for extra_cfg in ${FFMPEG_EXTRA_CONFIGURE:-}; do printf '%s\n' "$extra_cfg"; done
    if [ -n "$1" ]; then printf '%s\n' "--extra-ldsoflags=$1"; fi
}

build_ffmpeg() {
    # $1: pass name, $2: extra linker flags (may be empty)
    local pass="$1" extra="$2" src="$BUILD/$1/ffmpeg-$FFMPEG_VERSION" stage="$BUILD/$1/stage"
    rm -rf "$BUILD/$pass"
    mkdir -p "$BUILD/$pass"
    tar -xJf "$TARBALL" -C "$BUILD/$pass"
    local flags=()
    while IFS= read -r line; do flags+=("$line"); done < <(configure_flags "$extra")
    printf '%s\n' "./configure ${flags[*]}" > "$BUILD/$pass/configure_line.txt"
    (
        cd "$src"
        ./configure "${flags[@]}" > "$BUILD/$pass/configure.log" 2>&1 \
            || { tail -20 "$BUILD/$pass/configure.log" >&2; exit 1; }
        make -j"$(sysctl -n hw.ncpu)" > "$BUILD/$pass/make.log" 2>&1 \
            || { tail -30 "$BUILD/$pass/make.log" >&2; exit 1; }
        make install DESTDIR="$stage" > "$BUILD/$pass/install.log" 2>&1
    )
    echo "$stage$PREFIX/lib"
}

echo "==> pass 1: plain minimal build"
t0=$(date +%s)
LIB1=$(build_ffmpeg pass1 "")
echo "    built in $(( $(date +%s) - t0 )) s: $LIB1"
unresolved=$("$PY" -I "$HERE/spinvideo_unresolved.py" "$LIB1" "$VIDEO")
echo "    unresolved after pass 1:"; echo "${unresolved:-    (none)}" | sed 's/^/      /'
printf '%s\n' "$unresolved" > "$BUILD/unresolved_pass1.txt"
FINAL="$LIB1"; FINAL_PASS=pass1; forced=""
if [ -n "$unresolved" ]; then
    # Every ffmpeg lib links libavutil, so any of them can re-export a libavutil symbol: -u makes each
    # lib import it, and ffmpeg's export pattern (-exported_symbols_list with _av* & co.) re-exports it,
    # as in the Homebrew build Teledyne linked against.
    AVUTIL=$(ls "$LIB1"/libavutil.[0-9]*.[0-9]*.[0-9]*.dylib | head -1)
    for symbol in $(echo "$unresolved" | awk '{print $1}' | sort -u); do
        if ! nm -gU "$AVUTIL" | awk '$2 != "I" {print $3}' | grep -qx "$symbol"; then
            echo "ERROR: libSpinVideo imports symbols this minimal ffmpeg cannot provide:" >&2
            echo "$unresolved" >&2
            exit 1
        fi
        forced="$forced,-u,$symbol"
    done
    echo "==> pass 2: rebuilding with --extra-ldsoflags=-Wl$forced"
    t0=$(date +%s)
    LIB2=$(build_ffmpeg pass2 "-Wl$forced")
    echo "    built in $(( $(date +%s) - t0 )) s: $LIB2"
    unresolved=$("$PY" -I "$HERE/spinvideo_unresolved.py" "$LIB2" "$VIDEO")
    printf '%s\n' "$unresolved" > "$BUILD/unresolved_pass2.txt"
    if [ -n "$unresolved" ]; then
        echo "ERROR: still unresolved after the rebuild:" >&2
        echo "$unresolved" >&2
        exit 1
    fi
    echo "    unresolved after pass 2: (none)"
    FINAL="$LIB2"; FINAL_PASS=pass2
fi

echo "==> staging the payload candidate in $OUT"
rm -rf "$OUT/lib"
mkdir -p "$OUT/lib"
for name in avcodec avformat avutil swscale swresample; do
    cp -a "$FINAL"/lib"$name".*dylib "$OUT/lib"/
done
cp "$BUILD/$FINAL_PASS/configure_line.txt" "$OUT/configure_line.txt"
cp "$BUILD/$FINAL_PASS/ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" "$OUT/COPYING.LGPLv2.1"
cp "$BUILD/$FINAL_PASS/ffmpeg-$FFMPEG_VERSION/LICENSE.md" "$OUT/FFmpeg_LICENSE.md"
cp "$BUILD/$FINAL_PASS/ffmpeg-$FFMPEG_VERSION/ffbuild/config.mak" "$OUT/ffbuild_config.mak"
cp "$BUILD/$FINAL_PASS/ffmpeg-$FFMPEG_VERSION/config.h" "$OUT/config.h"
echo "final pass: $FINAL_PASS   extra ldsoflags: ${forced:+-Wl$forced}"
echo "done"
