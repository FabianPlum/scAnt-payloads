#!/bin/bash
# Removes scAnt from @PREFIX@ (written there by scAnt Setup). Files you made inside the app folder, such as
# projects saved there, are kept and listed. The system setup on Ubuntu (dialout group, udev rule, Teledyne's
# Spinnaker SDK) is left as it is; the end of this script says how to undo it.
set -u
PREFIX="@PREFIX@"
LAUNCHER="@LAUNCHER@"
[ -f "$PREFIX/install.json" ] || { echo "no scAnt installation in $PREFIX" >&2; exit 1; }
if pgrep -f "$PREFIX/env/bin/python" >/dev/null 2>&1; then echo "scAnt is running: quit it first" >&2; exit 1; fi
if [ "${1:-}" != --yes ]; then
    printf 'Remove scAnt from %s? [y/N] ' "$PREFIX"; read -r answer || answer=""
    case "$answer" in [Yy]*) ;; *) echo "Nothing was removed."; exit 0 ;; esac
fi
cd "$PREFIX" || exit 1
if [ -f flir/created-privacy-xml ]; then rm -f "$(cat flir/created-privacy-xml)"; fi
# the app tree: only the files scAnt Setup put there, and the tools it added
if [ -f app-files.txt ]; then
    while IFS= read -r f; do rm -f "app/$f"; done < app-files.txt
fi
rm -rf app/external/focus-stack app/SPLAT/external/colmap app/SPLAT/external/brush \
       app/scripts/rigstack/native/build app/APP_TREE_SHA.txt app/session_info.yml   # session_info.yml: scAnt's own state
find app -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
find app -depth -type d -empty -exec rmdir {} \; 2>/dev/null
rm -rf env tools flir bin payload-cache third_party_licenses app-files.txt install.json install-smoke.log
[ -n "$LAUNCHER" ] && rm -rf "$LAUNCHER"
if [ "@OS@" = linux ]; then rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/scant.png"; fi
rm -f uninstall.sh
if [ -d app ]; then
    echo "Kept (not installed by scAnt Setup):"; (cd app && find . -type f | sed 's|^\./|  app/|' | head -50)
    echo "scAnt is removed; $PREFIX holds only the files above and install.log."
else
    rm -f install.log; cd / && rmdir "$PREFIX" 2>/dev/null
    echo "scAnt is removed."
fi
if [ "@OS@" = linux ]; then
    echo "System setup, if you ran it: sudo gpasswd -d $(id -un) dialout; sudo rm /etc/udev/rules.d/99-scant-controller.rules;"
    echo "Teledyne's SDK: sudo sh remove_spinnaker.sh (from its download)."
fi
