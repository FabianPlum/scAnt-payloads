# scAnt focus-stack payload — PetteriAimonen/focus-stack (Windows x64)

[focus-stack](https://github.com/PetteriAimonen/focus-stack) by Petteri
Aimonen is scAnt's **default focus-stacking backend** (`scripts/stacking.py`)
and a mandatory part of every install (bundled with the core component, not
user-selectable). This payload repackages the **official, unmodified**
upstream Windows release flat into the layout scAnt expects
(`external/focus-stack/`: `focus-stack.exe` + OpenCV runtime DLLs).

## License

MIT (Petteri Aimonen) — `LICENSE.md` included, fetched from the upstream
tag. The bundled OpenCV runtime DLLs are Apache-2.0 (OpenCV project).

## Pinned input

- `focus-stack_Windows.zip` from upstream release tag **1.5** (2026-01-11),
  sha256 `0104c863e1fc961cd87520c87d41c927d2968822d48fd37e76da00e1dfb6c7c9`.
  The binary self-reports `1.3-42-g0cd289e` (upstream's release automation
  stamps `git describe` rather than the tag) with OpenCV 4.12.0.

## Validation (2026-07-21, reference machine)

- All CLI flags scAnt passes are supported: `--output`,
  `--no-whitebalance`, `--no-contrast`, `--align-keep-size`,
  `--full-resolution-align`, `--consistency`, `--denoise`, `--threads`,
  `--wait-images`, `--no-opencl`.
- Real-image stack runs green on both the OpenCL path and the
  `--no-opencl` CPU fallback (scAnt retries with the latter on transient
  GPU allocation failures).

## History note

Replaces the previous in-repo copy (`1.3-30-g953c7fa-dirty`, a local
Nov-2024 build with unpublished modifications — the provenance gap flagged
in REPRODUCING.md, now closed). Upstream 1.5 postdates that build.

## Verify

```powershell
external\focus-stack\focus-stack.exe --version   # 1.3-42-g0cd289e (tag 1.5)
```
