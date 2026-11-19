#!/bin/bash
# build_pkg.sh INSTALLER.sh OUT_DIR: builds scAnt-Setup-<version>-macos-arm64.pkg from the self-extracting macOS installer
# (build_installer.sh's output), so the package carries exactly the files of that installer.
#
# The package is a per-user ("home domain") product archive: no administrator rights; the Installer runs its
# postinstall as the user. Its payload is the installer's unpacked tree, put in ~/Library/scAnt/payload-cache/pkg-setup;
# the postinstall runs setup.sh from there (dialogs for FLIR support) and removes the tree when it is done. The
# postinstall's time limit is raised from the default 600 s to 3600 s (the environment download can take a while).
# Unsigned, as the other installers. Needs macOS (pkgbuild, productbuild, pkgutil).
set -euo pipefail
SH="${1:?usage: $0 scAnt-Setup-<version>-macos-arm64.sh OUT_DIR}"
OUT="${2:?usage: $0 INSTALLER.sh OUT_DIR}"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
B=$(mktemp -d "${TMPDIR:-/tmp}/scant-pkg.XXXXXX")
trap 'rm -rf "$B"' EXIT
mkdir -p "$OUT" "$B/scripts" "$B/resources"

bash "$SH" --extract-only "$B/root" > /dev/null
. "$B/root/pins.sh"
[ "$SCANT_PLATFORM" = macos-arm64 ] || { echo "$SH is not the macOS installer" >&2; exit 1; }
xattr -cr "$B/root"
cp "$HERE/postinstall" "$B/scripts/postinstall"; chmod 755 "$B/scripts/postinstall"
for f in welcome.html conclusion.html; do sed "s|@VERSION@|$SCANT_VERSION|g" "$HERE/resources/$f" > "$B/resources/$f"; done
sed "s|@VERSION@|$SCANT_VERSION|g" "$HERE/distribution.xml" > "$B/distribution.xml"

pkgbuild --root "$B/root" --scripts "$B/scripts" --identifier com.scant3d.scant.setup --version "$SCANT_VERSION" \
         --install-location "/Library/scAnt/payload-cache/pkg-setup" --ownership preserve "$B/component.pkg" > /dev/null
# the postinstall's time limit: 600 s by default, which a slow download of the environment can exceed
pkgutil --expand "$B/component.pkg" "$B/expanded"
sed -i '' 's/<postinstall file="\.\/postinstall"\/>/<postinstall file=".\/postinstall" timeout="3600"\/>/; s/timeout="600"/timeout="3600"/g' "$B/expanded/PackageInfo"
grep -q 'timeout="3600"' "$B/expanded/PackageInfo" || { echo "could not set the postinstall time limit" >&2; exit 1; }
mkdir -p "$B/pkgs"; pkgutil --flatten "$B/expanded" "$B/pkgs/scant-setup.pkg"

NAME="scAnt-Setup-$SCANT_VERSION-macos-arm64.pkg"
productbuild --distribution "$B/distribution.xml" --resources "$B/resources" --package-path "$B/pkgs" "$OUT/$NAME" > /dev/null
H=$(shasum -a 256 "$OUT/$NAME" | cut -d' ' -f1)
echo "$H  $NAME" > "$OUT/$NAME.sha256"
echo "built : $OUT/$NAME"
echo "from  : $(basename "$SH") $(shasum -a 256 "$SH" | cut -d' ' -f1)"
echo "sha256: $H"
echo "size  : $(wc -c < "$OUT/$NAME" | tr -d ' ') bytes"
