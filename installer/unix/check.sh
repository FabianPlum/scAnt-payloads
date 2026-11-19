#!/bin/bash
# scant-check: scAnt @VERSION@'s post-install checks (the Windows installer's smoke tests, INSTALLER_SPEC section 8).
# scAnt Setup runs it at the end and writes install-smoke.log; run it again any time. It needs no camera or
# controller and starts no GUI; with FLIR support it lists the connected cameras (read only).
here="$(cd "$(dirname "$0")" && pwd -P)"
. "$here/scant-env"
cd "$SCANT_PREFIX/app" || exit 1
PY="$SCANT_PREFIX/env/bin/python"
fails=0
check() { # check "name" CMD...
    local name="$1" out rc; shift
    out=$("$@" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then echo "ok    $name: $(printf '%s' "$out" | tail -1)"; else echo "FAIL  $name (exit $rc)"; fails=$((fails + 1)); fi
    printf '%s\n' "$out" | sed 's/^/        /'
}
echo "scAnt @VERSION@ checks, $(date '+%Y-%m-%d %H:%M:%S'), $SCANT_PREFIX"
check "Python environment" "$PY" -c "import cv2, PyQt5, serial, yaml, psutil, scipy, numpy, PIL, imutils, qdarktheme; print('imports OK, numpy', numpy.__version__, 'opencv', cv2.__version__)"
check "pip check" "$PY" -I -m pip check --disable-pip-version-check
check "Qt (offscreen)" env QT_QPA_PLATFORM=offscreen "$PY" -c "from PyQt5 import QtWidgets, QtCore; a = QtWidgets.QApplication(['scAnt']); print('Qt', QtCore.QT_VERSION_STR)"
check "shinestacker" "$PY" -c "
import sys
from PyQt5 import QtCore
from shinestacker.algorithms import StackJob, PyramidStack, DepthMapStack, AlignFrames
qt6 = [m for m in sys.modules if m.split('.')[0] in ('PySide6', 'shiboken6')]
assert not qt6, 'Qt6 loaded next to PyQt5: %s' % qt6
print('shinestacker OK, no Qt6')"
check "masking model" "$PY" -c "import cv2; cv2.ximgproc.createStructuredEdgeDetection('scripts/model.yml'); print('masking model OK')"
check "ExifTool" exiftool -ver
check "focus-stack" sh -c '"$1" --version 2>&1 | head -1' sh "@FOCUS_STACK@"
check "rig_stack" "$PY" -m scripts.rigstack status
check "scAnt version" "$PY" -c "from scripts.version import VERSION; assert VERSION == '@VERSION@', VERSION; print('scAnt', VERSION)"
if [ "@FLIR@" = yes ]; then
    check "PySpin" "$PY" -c "
import numpy, cv2, scipy
import PySpin
s = PySpin.System.GetInstance()
v = s.GetLibraryVersion()
c = s.GetCameras()
print('Spinnaker %d.%d.%d.%d, cameras: %d' % (v.major, v.minor, v.type, v.build, c.GetSize()))
c.Clear(); s.ReleaseInstance()"
fi
if [ -n "@COLMAP@" ]; then check "COLMAP" sh -c '"$1" help 2>&1 | head -3' sh "@COLMAP@"; fi
if [ -n "@BRUSH@" ]; then check "Brush" "@BRUSH@" --version; fi
echo "failures: $fails"
[ $fails -eq 0 ]
