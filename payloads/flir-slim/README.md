# scAnt slim FLIR payload — PySpin 4.2.0.88 + USB3 driver (Windows x64)

Everything needed to run scAnt with a FLIR USB3 camera (e.g. Blackfly S),
**without installing the full Spinnaker SDK**. The PySpin wheel is
self-contained: it bundles the entire Spinnaker runtime DLL set inside the
`PySpin/` package, so `import PySpin` works from a plain Python environment.

> **License**: proprietary — read `NOTICE.txt` and `licenses/FLIR_license.txt`
> before use. Installing this package means accepting the FLIR Spinnaker SDK
> License Agreement.

## Contents

| Path | What | Version |
|------|------|---------|
| `wheel/spinnaker_python-4.2.0.88-cp310-cp310-win_amd64.whl` | PySpin + complete Spinnaker runtime | 4.2.0.88 (Python 3.10, win_amd64) |
| `driver/PGRUsb3/` | WHQL-signed USB3 camera kernel driver | 2.7.3.640 |
| `licenses/` | FLIR EULA, SDK open-source notices, FFmpeg/LGPL texts | — |

## Requirements

- Windows 10/11 x64
- Python **3.10** (the wheel is cp310-only)
- `numpy >= 2.0` (declared wheel dependency)
- The Python environment must provide the MSVC 2015+ runtime
  (`MSVCP140.dll`, `VCRUNTIME140.dll`, `VCOMP140.dll`). Conda/micromamba
  environments ship it via the `vc14_runtime` package; otherwise install the
  Microsoft VC++ redistributable.

## Install

```powershell
# 1. Python library (no admin needed)
pip install wheel\spinnaker_python-4.2.0.88-cp310-cp310-win_amd64.whl

# 2. Kernel driver — one-time, admin required, WHQL-signed (silent)
pnputil /add-driver driver\PGRUsb3\PGRUSBCam3.inf /install
```

Connect the camera; it binds under device class **PGRDevices**.

## Verify

```powershell
python -c "import PySpin; s = PySpin.System.GetInstance(); v = s.GetLibraryVersion(); print(f'Spinnaker {v.major}.{v.minor}.{v.type}.{v.build}'); c = s.GetCameras(); print('cameras:', c.GetSize()); c.Clear(); s.ReleaseInstance()"
```

Expected: `Spinnaker 4.2.0.88` and your camera count.

## Uninstall

```powershell
pip uninstall spinnaker-python
# find the published driver name (oemNN.inf) for pgrusbcam3.inf, then:
pnputil /enum-drivers
pnputil /delete-driver oemNN.inf
```

## Notes

- USB3 cameras only. GigE cameras need the PGRLWF filter driver (not
  included) — install the full Spinnaker SDK from Teledyne for GigE.
- Diagnostics GUI (SpinView) and firmware tools are not included; they are
  available in the full Spinnaker SDK from
  https://www.teledynevisionsolutions.com/products/spinnaker-sdk/
- File integrity: see `SHA256SUMS.txt`.
