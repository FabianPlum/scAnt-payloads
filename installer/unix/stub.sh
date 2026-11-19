#!/bin/bash
# scAnt Setup @VERSION@ for @PLATFORM_TITLE@: a self-extracting installer.
#
#   bash @FILENAME@            (--help lists the options)
#
# It unpacks itself to a temporary folder, checks the SHA-256 of what it unpacked, and runs the installer in it
# (installer/unix/setup.sh in https://github.com/FabianPlum/scAnt-payloads). Nothing needs administrator rights;
# on Ubuntu the optional system setup asks for sudo. Built from scAnt_pro @APP_TREE_SHA@, payload set @PAYLOAD_SET@.
set -euo pipefail
ARCHIVE_SHA256="@ARCHIVE_SHA256@"
ARCHIVE_LINE=@ARCHIVE_LINE@
SELF="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/scant-setup.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
echo "Unpacking scAnt Setup @VERSION@ ..."
tail -n +"$ARCHIVE_LINE" "$SELF" > "$TMP/archive.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$TMP/archive.tar.gz" | cut -d' ' -f1)
else got=$(shasum -a 256 "$TMP/archive.tar.gz" | cut -d' ' -f1); fi
if [ "$got" != "$ARCHIVE_SHA256" ]; then
    echo "ERROR: this installer is damaged (its contents have SHA-256 $got, expected $ARCHIVE_SHA256). Download it again." >&2
    exit 1
fi
mkdir "$TMP/setup"
tar -xzf "$TMP/archive.tar.gz" -C "$TMP/setup"
rm -f "$TMP/archive.tar.gz"
if [ "${1:-}" = --extract-only ]; then
    dest="${2:?--extract-only needs a folder}"; mkdir -p "$dest"; cp -R "$TMP/setup/." "$dest/"; echo "extracted to $dest"; exit 0
fi
SCANT_SETUP_FILE="$SELF" bash "$TMP/setup/setup.sh" "$@"
exit $?
__SCANT_ARCHIVE__
