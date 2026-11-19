# Verbatim copy of the check embedded in scAnt_pro scripts/macos/setup_spinnaker_macos.sh
# (lines 151-180 at installer-v1.0.0 = b62b8e5): prints "symbol library" for every ffmpeg
# symbol libSpinVideo imports that the built ffmpeg libraries do not provide (two-level namespace).
# argv: <dir holding the ffmpeg libs by their major-versioned leaf names> <libSpinVideo dylib>
import os, re, subprocess, sys

spin_lib, video = sys.argv[1], sys.argv[2]

def out(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout

# nm -m names a library by its install-name stem, with or without the major
# version ("libavcodec.60", "libswscale")
libs = {}
for line in out("otool", "-L", video).splitlines()[1:]:
    name = os.path.basename(line.split()[0])
    if name.startswith(("libav", "libsw")):
        path = os.path.join(spin_lib, name)
        stem = name[:-len(".dylib")]
        libs[stem] = libs[stem.split(".")[0]] = path

exported = {}
for line in out("nm", "-m", video).splitlines():
    m = re.search(r"\(undefined\) (?:weak )?external (\S+) \(from (\S+)\)", line)
    if not m or m.group(2) not in libs:
        continue
    symbol, path = m.group(1), libs[m.group(2)]
    if path not in exported:
        # defined and re-exported ("I ... indirect for") symbols alike
        exported[path] = set(out("nm", "-gU", path).split())
    if symbol not in exported[path]:
        print(symbol, os.path.basename(path))
