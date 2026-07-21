# scAnt shinestacker payload — patched wheel (LGPL-3.0)

[shinestacker](https://github.com/lucalista/shinestacker) by Luca Lista
provides the focus-stacking algorithms scAnt uses (PyramidStack,
DepthMapStack, AlignFrames, …). scAnt ships it as a **prebuilt wheel from a
pinned upstream commit plus two small patches**, because upstream targets
Python ≥3.12 with a Qt GUI while scAnt needs the algorithms on Python 3.10
in a headless environment.

## Contents

| Path | What |
|------|------|
| `wheel/shinestacker-<ver>-py3-none-any.whl` | patched wheel (pure Python) |
| `source/shinestacker-<ver>-source+scant-patches.zip` | **corresponding source** for the wheel (upstream @ pinned SHA with patches applied) — LGPL-3.0 §6(d) |
| `patches/0001-relax-pyproject-for-py310.patch` | `requires-python >=3.10`, unpin numpy, drop PySide6/ipywidgets deps, license-field form |
| `patches/0002-guard-pyside6-import-for-headless.patch` | guards the unconditional `PySide6` import in `config/settings.py` so `shinestacker.algorithms` imports without Qt (falls back to upstream's own non-Qt config-dir logic) |
| `licenses/shinestacker-LICENSE-LGPL-3.0.txt` | upstream license text |

Pinned upstream commit: `fdea354652439ddc5aabcdac811a1cfcd05a2911`
(state of upstream `main`, validated with scAnt 2026-07-21).

## License

shinestacker is **LGPL-3.0**. The wheel is unmodified beyond the two patches
shipped here; the complete corresponding source is in `source/` and must
stay attached to the same release as the wheel. scAnt invokes shinestacker
as a Python library; scAnt itself remains MIT.

## Install

```powershell
pip install wheel\shinestacker-<ver>-py3-none-any.whl
```

Its pip dependencies (tifffile, rawpy, matplotlib, psdtags, imagecodecs,
jsonpickle, tqdm, Pygments, pytest, …) install automatically. None of them
pull Qt.

## Verify (INSTALLER_SPEC §8)

```powershell
python -c "from shinestacker.algorithms import StackJob, CombinedActions, AlignFrames, BalanceFrames, FocusStack, PyramidStack, DepthMapStack; print('shinestacker OK')"
```

## Upstream notes

- The PySide6 guard (patch 0002) is reported upstream as a
  headless-compatibility issue; if upstream adopts a fix, the patch drops.
- Upstream lists `pytest` in runtime dependencies; kept as-is to stay close
  to upstream (only GUI-only deps are removed).
- When Python is bumped to ≥3.12 (blocked on PySpin cp310, see
  INSTALLER_SPEC D5), patch 0001 mostly dissolves.
