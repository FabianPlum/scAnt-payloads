#!/bin/bash
# build_installer.sh: builds scAnt-Setup-<payloadSet>-<macos-arm64|ubuntu-x86_64>.sh, the self-extracting macOS and
# Ubuntu installers (the counterpart of ../build_installer.ps1 for Windows).
#
#   installer/unix/build_installer.sh --platform macos-arm64|linux-x86_64 --scant-repo DIR --rigstack-dir DIR \
#       [--ref REF] [--payload-dir DIR] [--out DIR]
#
#   --scant-repo    a scAnt_pro checkout; the app tree is `git archive <REF>` of it (default REF: HEAD)
#   --rigstack-dir  rig_stack's native library for the platform (libscant_stack.dylib or libscant_stack.so) with its
#                   scant_stack.json; git-ignored in scAnt_pro, so git archive cannot carry it. It must be built from
#                   the archived commit's sources (its sources_sha256 is checked against build.py's pin).
#   --payload-dir   folder with the payload archives (else they are downloaded from the manifest's URLs); every
#                   archive is checked against manifest-<platform>.json
#
# What the installer embeds: the pruned app tree with the library, and the payloads env-lock, focus-stack,
# shinestacker and (macOS) ffmpeg-spinvideo. It downloads COLMAP, Brush, the conda and PyPI packages at install time,
# and takes Teledyne's Spinnaker files from the customer. Needs bash, git, tar, curl, python3; for the macOS
# installer: nothing more (the app icon is written by python3).
set -euo pipefail

PLATFORM=""; REPO=""; REF=HEAD; RIG=""; PAYLOADS=""; OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --platform) PLATFORM="$2"; shift ;;
        --scant-repo) REPO="$2"; shift ;;
        --ref) REF="$2"; shift ;;
        --rigstack-dir) RIG="$2"; shift ;;
        --payload-dir) PAYLOADS="$2"; shift ;;
        --out) OUT="$2"; shift ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$PLATFORM" ] && [ -n "$REPO" ] && [ -n "$RIG" ] || { sed -n '2,20p' "$0"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HERE/../.." && pwd -P)"
MANIFEST="$ROOT/manifest-$PLATFORM.json"
[ -f "$MANIFEST" ] || { echo "no $MANIFEST" >&2; exit 1; }
case "$PLATFORM" in
    macos-arm64) LIB=libscant_stack.dylib; FILE_PLATFORM=macos-arm64; TITLE="macOS (Apple Silicon)" ;;
    linux-x86_64) LIB=libscant_stack.so; FILE_PLATFORM=ubuntu-x86_64; TITLE="Ubuntu (x86-64)" ;;
    *) echo "unknown platform $PLATFORM" >&2; exit 2 ;;
esac
OUT="${OUT:-$HERE/Output}"
BUILD="$HERE/build-$PLATFORM"
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
m() { python3 -I -c "import json,sys; m=json.load(open(sys.argv[1])); c={x['name']:x for x in m['components']}; print(eval(sys.argv[2]))" "$MANIFEST" "$1"; }

rm -rf "$BUILD"; mkdir -p "$BUILD/stage/app" "$BUILD/stage/payloads" "$BUILD/stage/third_party" "$BUILD/stage/launcher" "$BUILD/cache" "$OUT"
S="$BUILD/stage"
VERSION=$(m "m['payloadSet']"); TAG=$(m "m['tag']")

# ---- 1. app tree: tracked files at REF, pruned as for Windows ----
APP_SHA=$(git -C "$REPO" rev-parse "$REF^{commit}")
echo "app tree: scAnt_pro @ $APP_SHA"
git -C "$REPO" archive "$APP_SHA" | tar -x -C "$S/app"
APP_VERSION=$(sed -n 's/^VERSION = "\(.*\)"$/\1/p' "$S/app/scripts/version.py")
[ "$APP_VERSION" = "$VERSION" ] || { echo "scripts/version.py says $APP_VERSION, the manifest's payload set is $VERSION" >&2; exit 1; }
# the Windows tools at external/'s top level (legacy Hugin suite, exiftool.exe) and Windows ExifTool's files;
# both environments carry ExifTool 13.59, which scAnt finds on PATH
find "$S/app/external" -maxdepth 1 -type f ! -name cameraMakes.txt ! -name cameraSensors.txt -delete
rm -rf "$S/app/external/exiftool_files"
rm -rf "$S/app/docs" "$S/app/legacy_scripts" "$S/app/tests" "$S/app/scAnt_macOS.command"
# closed sources (scAnt_pro's .gitattributes leaves them out of git archive already)
rm -rf "$S/app/scripts/Arduino_Control" "$S/app/scripts/SKR_Control" "$S/app/scripts/rigstack/native" "$S/app/scripts/rigstack/README.md"
src=$(find "$S/app" -type f \( -name '*.ino' -o -name '*.cpp' -o -name '*.cu' -o -name '*.cuh' -o -name '*.c' -o -name '*.h' -o -name CMakeLists.txt \))
[ -z "$src" ] || { echo "the app tree holds sources that must not ship: $src" >&2; exit 1; }

# ---- 2. rig_stack's library ----
mkdir -p "$S/app/scripts/rigstack/native/build"
cp "$RIG/$LIB" "$RIG/scant_stack.json" "$S/app/scripts/rigstack/native/build/"
python3 -I - "$S/app/scripts/rigstack/native/build" "$LIB" "$S/app/scripts/rigstack/build.py" <<'EOF'
import hashlib, json, re, sys
d, lib, build = sys.argv[1:4]
rec = json.load(open(f"{d}/scant_stack.json"))
got = hashlib.sha256(open(f"{d}/{lib}", "rb").read()).hexdigest()
assert rec["library"] == lib and rec["sha256"] == got, f"{lib} does not match its scant_stack.json"
pin = re.search(r'SOURCES_SHA256 = "([0-9a-f]{64})"', open(build).read()).group(1)
assert rec["sources_sha256"] == pin, f"{lib} was built from sources {rec['sources_sha256']}, not this commit's ({pin})"
print(f"rig_stack library: {lib} sha256 {got}, {rec.get('compiler')}")
EOF
RIG_SHA=$(sha256_of "$S/app/scripts/rigstack/native/build/$LIB")

# ---- 3. firmware builds match their manifest ----
python3 -I - "$S/app/firmware/skr" <<'EOF'
import hashlib, json, sys
d = sys.argv[1]; fw = json.load(open(f"{d}/manifest.json"))
for b in fw["builds"]:
    assert hashlib.sha256(open(f"{d}/{b['file']}", "rb").read()).hexdigest() == b["sha256"], b["file"]
print(f"controller firmware: scAnt-SKR {fw['version']}, {len(fw['builds'])} builds")
EOF
echo "$APP_SHA" > "$S/app/APP_TREE_SHA.txt"

# ---- 4. payloads, checked against the manifest and their own SHA256SUMS.txt ----
payload() { # payload NAME -> path of the verified archive
    local url sha file
    url=$(m "c['$1']['url']"); sha=$(m "c['$1']['sha256']"); file=$(basename "$url")
    if [ -n "$PAYLOADS" ] && [ -f "$PAYLOADS/$file" ]; then cp "$PAYLOADS/$file" "$BUILD/cache/$file"
    else curl -fL --retry 5 -sS -o "$BUILD/cache/$file" "$url"; fi
    [ "$(sha256_of "$BUILD/cache/$file")" = "$sha" ] || { echo "$file does not match the manifest" >&2; exit 1; }
    echo "$BUILD/cache/$file"
}
sums() { (cd "$1" && LC_ALL=C sed $'1s/^\xef\xbb\xbf//' SHA256SUMS.txt | tr -d '\r' | \
          { if command -v sha256sum >/dev/null 2>&1; then sha256sum --quiet -c -; else shasum -a 256 --quiet -c -; fi; }) \
          || { echo "$1: SHA256SUMS.txt does not match" >&2; exit 1; }; }
for name in env-lock focus-stack; do
    mkdir -p "$S/payloads/$name"; tar -xzf "$(payload $name)" -C "$S/payloads/$name"; sums "$S/payloads/$name"
done
x="$BUILD/shinestacker"; mkdir -p "$x"
(cd "$x" && python3 -I -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall('.')" "$(payload shinestacker)")
sums "$x"
mkdir -p "$S/payloads/shinestacker/wheel" "$S/third_party/shinestacker"
cp "$x"/wheel/*.whl "$S/payloads/shinestacker/wheel/"
cp -R "$x/source" "$x/patches" "$x/licenses" "$S/third_party/shinestacker/"   # LGPL: the corresponding source travels with the wheel
if [ "$PLATFORM" = macos-arm64 ]; then
    mkdir -p "$S/payloads/ffmpeg-spinvideo"; tar -xzf "$(payload ffmpeg-spinvideo)" -C "$S/payloads/ffmpeg-spinvideo"
    sums "$S/payloads/ffmpeg-spinvideo"
    mkdir -p "$S/third_party/ffmpeg"
    cp "$S/payloads/ffmpeg-spinvideo/licenses/"* "$S/payloads/ffmpeg-spinvideo/configure_line.txt" "$S/payloads/ffmpeg-spinvideo/README.md" "$S/third_party/ffmpeg/"
fi
mkdir -p "$S/third_party/micromamba" "$S/third_party/focus-stack"
cp "$S/payloads/env-lock/licenses/micromamba_LICENSE.txt" "$S/third_party/micromamba/"
cp "$S/payloads/focus-stack/LICENSE.md" "$S/third_party/focus-stack/"
cp "$S/app/NOTICE" "$S/third_party/NOTICE-scAnt.txt"
cp "$HERE/THIRD-PARTY-NOTICES-$PLATFORM.txt" "$S/third_party/THIRD-PARTY-NOTICES.txt"

# ---- 5. installer scripts, launcher, pins ----
cp "$HERE/setup.sh" "$HERE/check.sh" "$HERE/uninstall.sh" "$S/"
if [ "$PLATFORM" = macos-arm64 ]; then
    cp "$HERE/launcher/Info.plist" "$S/launcher/"
    # an .icns holding a 256 px PNG (type ic08), written directly (sips needs a writable system temp folder);
    # resized with Pillow when the build's python3 has it (PYTHON_PIL names another interpreter)
    "${PYTHON_PIL:-python3}" -I - "$S/app/images/scAnt_icon.png" "$S/launcher/scAnt.icns" <<'PYEOF'
import io, struct, sys
data = open(sys.argv[1], "rb").read()
try:
    from PIL import Image
    buf = io.BytesIO(); Image.open(io.BytesIO(data)).convert("RGBA").resize((256, 256), Image.LANCZOS).save(buf, "PNG"); data = buf.getvalue()
except ImportError:
    pass
entry = b"ic08" + struct.pack(">I", len(data) + 8) + data
open(sys.argv[2], "wb").write(b"icns" + struct.pack(">I", len(entry) + 8) + entry)
PYEOF
else
    cp "$HERE/launcher/scant.desktop" "$S/launcher/"
    cp "$S/app/images/scAnt_icon.png" "$S/launcher/scant.png"
fi
mb() { python3 -I -c "print(round(int(__import__('sys').argv[1]) / 1e6))" "$1"; }
{
    echo "# generated by build_installer.sh from manifest-$PLATFORM.json (payload set $VERSION, $TAG): do not edit"
    echo "SCANT_VERSION=$VERSION"; echo "SCANT_PLATFORM=$PLATFORM"; echo "APP_TREE_SHA=$APP_SHA"
    echo "PAYLOAD_SET=\"$VERSION ($TAG)\""; echo "RIGSTACK_SHA256=$RIG_SHA"
    echo "SHINESTACKER_VERSION=$(m "c['shinestacker']['version']")"
    echo "SHINESTACKER_WHEEL=$(basename "$S"/payloads/shinestacker/wheel/*.whl)"
    echo "FLIR_VERSION=$(m "c['flir-spinnaker']['version']")"
    echo "COLMAP_VERSION=$(m "c['colmap']['version']")"; echo "BRUSH_VERSION=$(m "c['brush']['version']")"
    echo "BRUSH_URL=$(m "c['brush']['url']")"; echo "BRUSH_SHA256=$(m "c['brush']['sha256']")"; echo "BRUSH_SIZE_MB=$(mb "$(m "c['brush']['size']")")"
    if [ "$PLATFORM" = macos-arm64 ]; then
        echo "ENV_LOCK=scAnt_pro-osx-arm64.lock"; echo "ENV_REQUIREMENTS=requirements-macos-arm64.txt"
        echo "FLIR_PKG_NAME=$(m "c['flir-spinnaker']['files'][0]['file']")"; echo "FLIR_PKG_SHA256=$(m "c['flir-spinnaker']['files'][0]['sha256']")"
        echo "COLMAP_URL=$(m "c['colmap']['url']")"; echo "COLMAP_SHA256=$(m "c['colmap']['sha256']")"; echo "COLMAP_SIZE_MB=$(mb "$(m "c['colmap']['size']")")"
    else
        echo "ENV_LOCK=scAnt_pro-linux-64.lock"; echo "ENV_REQUIREMENTS=requirements-linux-x86_64.txt"
        echo "COLMAP_CPU_LOCK=colmap-cpu-linux-64.lock"; echo "COLMAP_CUDA_LOCK=colmap-cuda-linux-64.lock"; echo "COLMAP_CUDA_MIN_DRIVER=575"
        for i in 0 1 2; do
            f=$(m "c['flir-spinnaker']['files'][$i]['file']"); h=$(m "c['flir-spinnaker']['files'][$i]['sha256']")
            case "$f" in *jammy*) v=FLIR_SDK_JAMMY ;; *noble*) v=FLIR_SDK_NOBLE ;; *) v=FLIR_PY ;; esac
            echo "${v}_NAME=$f"; echo "${v}_SHA256=$h"
        done
    fi
} > "$S/pins.sh"
chmod 755 "$S/setup.sh" "$S/check.sh" "$S/uninstall.sh"

# ---- 6. archive + self-extracting stub ----
ARCHIVE="$BUILD/archive.tar.gz"
COPYFILE_DISABLE=1 tar $( [ "$(uname -s)" = Darwin ] && echo "--no-mac-metadata --no-xattrs" ) -czf "$ARCHIVE" -C "$S" .
ARCHIVE_SHA=$(sha256_of "$ARCHIVE")
NAME="scAnt-Setup-$VERSION-$FILE_PLATFORM.sh"
lines=$(grep -n '^__SCANT_ARCHIVE__$' "$HERE/stub.sh" | cut -d: -f1)
sed -e "s|@VERSION@|$VERSION|g" -e "s|@PLATFORM_TITLE@|$TITLE|g" -e "s|@FILENAME@|$NAME|g" -e "s|@APP_TREE_SHA@|$APP_SHA|g" \
    -e "s|@PAYLOAD_SET@|$VERSION ($TAG)|g" -e "s|@ARCHIVE_SHA256@|$ARCHIVE_SHA|g" -e "s|@ARCHIVE_LINE@|$((lines + 1))|g" \
    "$HERE/stub.sh" > "$OUT/$NAME"
cat "$ARCHIVE" >> "$OUT/$NAME"
chmod 755 "$OUT/$NAME"
H=$(sha256_of "$OUT/$NAME")
echo "$H  $NAME" > "$OUT/$NAME.sha256"
echo "built : $OUT/$NAME"
echo "sha256: $H"
echo "size  : $(wc -c < "$OUT/$NAME" | tr -d ' ') bytes"
echo "rig_stack: $LIB $RIG_SHA"
