# env-lock for macOS and Ubuntu

The scAnt pro Python environment for the macOS (Apple Silicon) and Ubuntu (x86-64) installers. The Windows env-lock
is described in [`../README.md`](../README.md).

The payload `scAnt-payload-env-lock_<version>_<platform>.tar.gz` contains:

| File | What |
|---|---|
| `micromamba` | micromamba 2.8.1-0 (`micromamba-osx-arm64` or `micromamba-linux-64` from mamba-org/micromamba-releases, unmodified; BSD-3-Clause, `licenses/micromamba_LICENSE.txt`) |
| `scAnt_pro-osx-arm64.lock` / `scAnt_pro-linux-64.lock` | explicit conda lock (`url#md5` per package, conda-forge); the `.sha256` files list each package's SHA-256 |
| `requirements-macos-arm64.txt` / `requirements-linux-x86_64.txt` | the pip layer, one PyPI file per line with its SHA-256 |
| `colmap-cpu-linux-64.lock`, `colmap-cuda-linux-64.lock` | Ubuntu only: COLMAP 4.2.1 from conda-forge, in an environment of its own (it uses Qt 6, which must not share a process with scAnt's PyQt5) |

## How the installer uses it

```bash
micromamba create -y --no-rc -p <install>/env --file scAnt_pro-<subdir>.lock      # MAMBA_ROOT_PREFIX, CONDA_PKGS_DIRS in <install>/payload-cache
<install>/env/bin/python -I -m pip install --isolated --no-deps --require-hashes --no-build-isolation -r requirements-<platform>.txt
<install>/env/bin/python -I -m pip install --isolated --no-deps --no-index shinestacker-<ver>-py3-none-any.whl
# FLIR: Teledyne's PySpin wheel from the customer's own download, --no-deps
```

pip never resolves dependencies, so it cannot replace conda's numpy, OpenCV or PyQt5.

## Where the pins come from

- **macOS:** `conda list --explicit --md5` of the developer environment the macOS port was validated in (Python 3.10.22,
  numpy 1.26.4, 180 packages). numpy stays at 1.26 because Teledyne's macOS PySpin wheel (4.4.0.246, cp310) is built
  against the numpy 1.x C API and declares `numpy<2.0`. The environment also carries conda-forge's ExifTool 13.59 (the
  version the Windows installer ships), which scAnt finds on `PATH`.
- **Ubuntu:** solved on 2026-11-19 with mamba 2.9.0 for linux-64 and glibc 2.35 (Ubuntu 22.04) from
  `python=3.10 pip numpy=1.26.* libblas=*=*openblas libcblas=*=*openblas liblapack=*=*openblas opencv=4.13.*=headless*
  pyqt=5.15.* pillow=12.* scipy=1.15.* psutil exiftool=13.59`: the macOS set. numpy is 1.26 because Teledyne's Linux
  PySpin wheel 4.4.0.246 also declares `numpy<2.0`; conda-forge's matplotlib and scikit-image are left out (the app
  does not import them; matplotlib comes from PyPI for shinestacker, without Qt).
- **COLMAP (Ubuntu):** `colmap=4.2.1=cpu_gpl_h68f24ef_409` and `colmap=4.2.1=cuda_129gpl_h960d87c_409` (CUDA 12.9,
  NVIDIA driver 575 or later), solved the same day.
- **pip layer:** the files the validated macOS environment holds (darkdetect, imutils, pyqtdarktheme, pyserial,
  PyYAML, and shinestacker's dependencies: contourpy, cycler, fonttools, imagecodecs, jsonpickle, kiwisolver,
  matplotlib, psdtags, pyparsing, python-dateutil, rawpy, six, tifffile, tqdm, tzdata), the same versions for Linux,
  plus gphoto2 2.4.0 (DSLR cameras on Linux). imutils has no wheel: its sdist builds at install.
