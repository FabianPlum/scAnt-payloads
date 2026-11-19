#!/bin/bash
# build_unix_payloads.sh PLATFORM OUT_DIR [INPUT_DIR]
#
# Builds the macOS (macos-arm64) or Ubuntu (linux-x86_64) payloads of a payload set from pinned inputs:
#
#   scAnt-payload-env-lock_<ver>_<platform>.tar.gz           micromamba + explicit conda lock(s) + hash-pinned pip
#                                                            layer (payloads/env-lock/unix/)
#   scAnt-payload-focus-stack_1.5_<platform>.tar.gz          the official focus-stack 1.5 release, unmodified
#   scAnt-payload-ffmpeg-spinvideo_6.1.6_macos-arm64.tar.gz  (macOS) the LGPL ffmpeg 6 Teledyne's libSpinVideo
#                                                            needs; from FFMPEG_BUILD (payloads/ffmpeg-spinvideo/)
#
# shinestacker is the pure-Python wheel of payload set v1.0.0 and is not rebuilt. Inputs are downloaded into
# INPUT_DIR (default OUT_DIR/inputs) unless already there, and every one is checked against its pinned SHA-256.
# Archives are tar.gz made without macOS metadata (zip tools break signed app bundles); each holds a
# SHA256SUMS.txt of its files. Runs on macOS (bsdtar, shasum, ditto); the macOS focus-stack payload needs ditto.
set -euo pipefail

PLATFORM="${1:?usage: $0 macos-arm64|linux-x86_64 OUT_DIR [INPUT_DIR]}"
OUT="${2:?usage: $0 PLATFORM OUT_DIR [INPUT_DIR]}"
IN="${3:-$OUT/inputs}"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
ENV_LOCK_VERSION="2026.11.19"
MICROMAMBA_VERSION="2.8.1-0"
mkdir -p "$OUT" "$IN"

case "$PLATFORM" in
    macos-arm64)
        MM_NAME=micromamba-osx-arm64; MM_SHA256=de71a646b73af92dd663e6ddc78993a6a4d47ea28b5d8908c3cc2b9c3077e528
        FS_NAME=focus-stack_MacOSX.zip; FS_SHA256=332b0667c0edd92c75c37b56476c46ca2aa729bb2aa63476bb5704776300ea96
        LOCKS="scAnt_pro-osx-arm64.lock requirements-macos-arm64.txt" ;;
    linux-x86_64)
        MM_NAME=micromamba-linux-64; MM_SHA256=9689782d863c05a1bf5d2d371ba527104e7a4eb4310c1637d8653b751aed9c82
        FS_NAME=focus-stack.AppImage; FS_SHA256=97740c829bbd1d9f873c09694a58f22944c9ec8237d3a30360877960b3bff865
        LOCKS="scAnt_pro-linux-64.lock scAnt_pro-linux-64.lock.sha256 colmap-cpu-linux-64.lock colmap-cpu-linux-64.lock.sha256 colmap-cuda-linux-64.lock colmap-cuda-linux-64.lock.sha256 requirements-linux-x86_64.txt" ;;
    *) echo "unknown platform $PLATFORM" >&2; exit 2 ;;
esac
FS_LICENSE_SHA256=5e11fc4bce97ec54bfe65e8b74da8010fd1d7f2427d35f28e3cab25607109e57

fetch() { # fetch URL FILE SHA256
    if [ ! -f "$IN/$2" ]; then curl -fL --retry 5 -sS -o "$IN/$2.part" "$1" && mv "$IN/$2.part" "$IN/$2"; fi
    echo "$3  $IN/$2" | shasum -a 256 -c - > /dev/null || { echo "ERROR: $2 does not match its pin $3" >&2; exit 1; }
}
pack() { # pack STAGE ARCHIVE: SHA256SUMS.txt, then a tar.gz without macOS metadata
    (cd "$1" && find . -type f ! -name SHA256SUMS.txt -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | sed 's|  \./|  |') > "$1/SHA256SUMS.txt"
    COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname root -czf "$2" -C "$1" .
    printf '%s  %s  %s bytes\n' "$(shasum -a 256 "$2" | cut -d' ' -f1)" "$(basename "$2")" "$(wc -c < "$2" | tr -d ' ')"
}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/scant-payloads.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# --- env-lock ---
fetch "https://github.com/mamba-org/micromamba-releases/releases/download/$MICROMAMBA_VERSION/$MM_NAME" "$MM_NAME" "$MM_SHA256"
S="$WORK/env-lock"; mkdir -p "$S/licenses"
cp "$IN/$MM_NAME" "$S/micromamba"; chmod 755 "$S/micromamba"
for f in $LOCKS; do cp "$HERE/env-lock/unix/$f" "$S/"; done
cp "$HERE/env-lock/micromamba_LICENSE.txt" "$S/licenses/"
cp "$HERE/env-lock/unix/README.md" "$S/README.md"
pack "$S" "$OUT/scAnt-payload-env-lock_${ENV_LOCK_VERSION}_${PLATFORM}.tar.gz"

# --- focus-stack ---
fetch "https://github.com/PetteriAimonen/focus-stack/releases/download/1.5/$FS_NAME" "$FS_NAME" "$FS_SHA256"
fetch "https://raw.githubusercontent.com/PetteriAimonen/focus-stack/1.5/LICENSE.md" focus-stack_LICENSE.md "$FS_LICENSE_SHA256"
S="$WORK/focus-stack"; mkdir -p "$S"
if [ "$PLATFORM" = macos-arm64 ]; then
    # ditto keeps the bundle's symlinks and signature; the app is upstream's, unmodified
    ditto -x -k --noqtn "$IN/$FS_NAME" "$WORK/fs-zip"
    ditto --noqtn "$WORK/fs-zip/focus-stack/focus-stack.app" "$S/focus-stack.app"
else
    cp "$IN/$FS_NAME" "$S/focus-stack.AppImage"; chmod 755 "$S/focus-stack.AppImage"
fi
cp "$IN/focus-stack_LICENSE.md" "$S/LICENSE.md"
cp "$HERE/focus-stack/README-unix.md" "$S/README.md"
pack "$S" "$OUT/scAnt-payload-focus-stack_1.5_${PLATFORM}.tar.gz"

# --- ffmpeg-spinvideo (macOS) ---
if [ "$PLATFORM" = macos-arm64 ]; then
    B="${FFMPEG_BUILD:?set FFMPEG_BUILD to the output folder of payloads/ffmpeg-spinvideo/build_ffmpeg.sh}"
    S="$WORK/ffmpeg"; mkdir -p "$S/lib" "$S/licenses"
    cp -a "$B"/lib/lib{avcodec,avformat,avutil,swscale,swresample}.*dylib "$S/lib/"
    cp "$B/COPYING.LGPLv2.1" "$B/FFmpeg_LICENSE.md" "$S/licenses/"
    cp "$B/configure_line.txt" "$S/"
    cp "$HERE/ffmpeg-spinvideo/README.md" "$S/README.md"
    pack "$S" "$OUT/scAnt-payload-ffmpeg-spinvideo_6.1.6_macos-arm64.tar.gz"
fi
echo "done: $OUT"
