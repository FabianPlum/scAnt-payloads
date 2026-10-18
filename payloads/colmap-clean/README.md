# scAnt colmap-clean payload — COLMAP 4.1.1 without its GPL, AGPL and non-commercial parts (Windows x64)

**A separate item, not part of the installer's payload set.** It is not in
[`manifest.json`](../../manifest.json), and the scAnt_pro installer never
downloads it. It is consumed by scAnt_API's `tools/fetch_tools.py --tool
colmap-clean`, which pins the archive's address, SHA-256 and size
(`tools/pins.toml`, `[tools.colmap-clean]`). It is released under its own tag,
`colmap-clean-<version>`, never under a `v*` payload-set tag.

## What it is

[COLMAP](https://github.com/colmap/colmap) 4.1.1 (tag `4.1.1`, commit
`a0d785f`) built from source for scAnt, with CUDA for PatchMatch stereo and
ONNX Runtime for ALIKED features and LightGlue matching. Upstream's own
Windows build carries or links parts whose licences a closed product cannot
take; this build leaves each of them out. COLMAP itself is BSD-3-Clause.

| Left out | Licence | Why, and what it changes |
|---|---|---|
| The GUI (Qt) and OpenGL | Qt: LGPL-3.0 | scAnt runs COLMAP from the command line only; the GUI is the only user of Qt and OpenGL. |
| CGAL, with GMP and MPFR | GPL-3.0 (GMP, MPFR: LGPL-3.0) | Linking it puts the whole binary under the GPL. What needs it (Delaunay meshing, the mesh texturer's occlusion test) is not available. |
| LSD, the line segment detector | AGPL-3.0 | Only line detection uses it; scAnt does not. |
| SiftGPU | non-commercial | SIFT runs on the CPU (VLFeat). A SIFT extraction or match with `use_gpu` fails its option check instead of falling back silently. CUDA stays for PatchMatch. |
| SuiteSparseQR (SPQR); CHOLMOD's Supernodal, MatrixOps, Modify and GPU modules | GPL-2.0-or-later | Ceres takes Eigen's sparse QR for the covariance, and CHOLMOD factorises simplicially. Bundle adjustment of up to 50 images is dense Schur and does not use CHOLMOD. |
| ONNX Runtime's CUDA provider | needs NVIDIA cuDNN and cuBLAS | ALIKED and LightGlue run on the CPU. |
| Downloads at run time (no curl, no OpenSSL) | — | A run names its model files (`models/`). |

**What remains:** COLMAP (BSD-3-Clause) with VLFeat (BSD-2-Clause),
PoissonRecon (MIT), PoseLib (BSD-3-Clause), Faiss (MIT), Eigen (MPL-2.0) and
Boost (BSL-1.0) compiled in; NVIDIA's CUDA runtime, linked statically, which
the CUDA Toolkit licence allows as distributable code; 37 shared libraries,
all permissive except CHOLMOD and libquadmath (LGPL-2.1-or-later, shipped
unmodified as separate libraries, with their source in `NOTICE.txt`) and
the GCC runtime (GPL-3.0-or-later with the GCC Runtime Library Exception);
and four ONNX models: ALIKED (BSD-3-Clause), LightGlue's ALIKED weights
(Apache-2.0) and COLMAP's brute-force matcher (BSD-3-Clause). `NOTICE.txt`
names every component with its version and licence; `licences/` holds their
texts; `licence-proof.json` holds the import tables that show what each
binary links.

## Versions

| Part | Version |
|---|---|
| COLMAP | 4.1.1, commit `a0d785fba74b2664f31edc4a29026a8b27c00f67` |
| vcpkg (COLMAP 4.1.1's baseline) | `a0b1c8d3a477c1cb4813d8e127a56961707ca42b` |
| Compiler | MSVC 14.44.35207 (Visual Studio 2022) |
| CUDA | 12.8, for compute capability 7.5 to 12.0 (`75-real;80-real;86-real;89-real;90-real;120-real;120-virtual`) |
| Ceres Solver | 2.2.0, overlay port without SuiteSparseQR |
| SuiteSparse | 7.12.2 (CHOLMOD 5.3.4) |
| ONNX Runtime | 1.24.4, CPU provider |
| ONNX models | COLMAP's release 3.13.0 files |
| Build of record | 2026-10-17; `manifest.json` sha256 `b7906d8d3f55357d5e504fcbed077252323aa0251784cc92ae55c1c9f6c64909`, `bin/colmap.exe` sha256 `7d731548bcf20e679f1f3287c25a433c907bc9b21f453405202b7a8246094f4d` |

## Archive layout

```
bin/                 colmap.exe and the 37 libraries it loads
licences/            the licence of every library shipped or linked, and of each model
models/              aliked-n16rot.onnx, aliked-n32.onnx, aliked-lightglue.onnx, bruteforce-matcher.onnx
manifest.json        every file of the build and its sha256, with the sources' pins
licence-proof.json   the import and export tables, the build graph's definitions, vcpkg's ports
NOTICE.txt           every third-party component and its licence; the LGPL source
README.md            this file
SHA256SUMS.txt       every file of the archive
```

Requirements: Windows 10 or 11, x64; the Microsoft Visual C++ 2015-2022
runtime (x64), which is not shipped, as in upstream's build. PatchMatch
stereo needs an NVIDIA card of compute capability 7.5 or higher with a driver
for CUDA 12.8; feature extraction, matching and mapping run on the CPU.

## Verify

```powershell
bin\colmap.exe version   # COLMAP 4.1.1 (Commit a0d785fb on 2026-07-17 with CUDA)
```

The archive's SHA-256 and size are in the release's `SHA256SUMS.txt` and in
scAnt_API's pin; the files inside are checked by the in-archive
`SHA256SUMS.txt` and by `manifest.json`.

## Rebuilding

`build/` is the recipe, byte-identical to scAnt_API's `tools/` at main
`f7853f13`: `build_colmap.py`, the COLMAP patch (`colmap_patches/`), the
overlay ports (`colmap_ports/`: Ceres, the triplet) and the excerpt of
`pins.toml` it reads. With Visual Studio 2022 (MSVC 14.44), CUDA 12.8, Git and
Python 3.11 or newer, run from `build\`:

```powershell
py -3.12 tools\build_colmap.py --cache C:\vc --dest <dir>   # about 30 min; its docstring says each step
```

then `.\build_payload.ps1 -BuildDir <dir>\colmap-clean -ManifestSha256 <...>
-ExecutableSha256 <...> -Version 4.1.1-2` with the lines the build printed.
The bytes are not reproducible (COLMAP and vcpkg's ports have no `/Brepro`):
a rebuild is a new payload version and a new tag. Published assets are never
replaced in place.
