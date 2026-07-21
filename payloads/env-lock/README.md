# scAnt env-lock payload — locked Python environment (Windows x64)

Everything the installer needs to create the `scAnt_pro` Python environment
deterministically: **micromamba** (single static exe) plus the
**conda-lock**-rendered lockfiles for the audited environment spec
(`conda_environment/scAnt_Pro_WINDOWS.yml` in the scAnt repo).

Conda packages themselves are *not* bundled — micromamba downloads them from
conda-forge's CDN at install time, pinned to exact builds + hashes by the
lockfile. (A mirrored local channel for fully-offline installs is a possible
later addition — see INSTALLER_SPEC D6.)

## Contents

| Path | What |
|------|------|
| `micromamba.exe` | micromamba (static, BSD-3) — pinned release |
| `scAnt_pro-win-64.lock` | explicit lockfile (conda packages, exact URLs + hashes; `# pip` lines carry the pip pins) |
| `conda-lock.yml` | unified conda-lock (source of the explicit render; use for re-render/upgrades) |
| `licenses/micromamba_LICENSE.txt` | BSD-3-Clause license of mamba/micromamba |

## Create the environment

```powershell
micromamba.exe create -y -p <install>\env --file scAnt_pro-win-64.lock
# pip-pinned pure-python deps (imutils, pyqtdarktheme, pyserial, PyYAML):
<install>\env\python.exe -m pip install --no-deps imutils==0.5.4 pyqtdarktheme==2.1.0 pyserial==3.5 PyYAML==6.0.3
```

Afterwards the installer adds the application wheels on top:

```powershell
# from the flir-slim payload (EULA-gated):
<install>\env\python.exe -m pip install <flir-slim>\wheel\spinnaker_python-4.2.0.88-cp310-cp310-win_amd64.whl
# shinestacker patched wheel (own payload, LGPL-3.0) — brings tifffile, rawpy,
# tqdm, psdtags, imagecodecs, jsonpickle as pip dependencies
```

## Smoke test (INSTALLER_SPEC §8)

```powershell
<install>\env\python.exe -c "import cv2, PyQt5, serial, yaml, psutil, scipy, numpy, PIL, imutils; print('env OK')"
```

## Environment notes (audit of 2026-07-21)

- OpenCV is the **headless** conda-forge variant: the scAnt GUI renders
  frames via PyQt5; `cv2.imshow` is only used by standalone dev/demo
  scripts. For those, use a dev env with `opencv=*=qt6*` (or pip
  `opencv-python`).
- matplotlib, scikit-image, PySide6/Qt6 are deliberately absent (unused by
  the application). Dev extras: `pip install matplotlib pytest ruff`.
- Python 3.10 is required by the PySpin cp310 wheel; numpy 2.2.x matches
  the validated stack.
