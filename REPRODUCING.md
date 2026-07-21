# Reproducing payloads

Every payload in this repository can be rebuilt from official upstream
inputs. This document is the process; per-payload specifics live in
`payloads/<name>/` (each payload directory contains `build_payload.ps1`,
`inputs.json`, `README.md`, and — for non-open-source payloads — a
`NOTICE.txt`).

## What "reproducible" means here

- **Content-level, not byte-level.** Zip containers are not byte-stable
  across rebuilds (timestamps, compressor version), so two correct builds of
  the same payload have different outer SHA-256s. What must match is the
  **content**: every file listed in the archive's `SHA256SUMS.txt` except
  the version-controlled docs (`README.md`, `NOTICE.txt`, `SHA256SUMS.txt`
  itself) must be hash-identical to the published archive and to the pinned
  inputs.
- **The outer zip hash is pinned at release time.** `manifest.json` records
  the SHA-256 + size of the exact published asset. The installer verifies
  that pin. A rebuilt zip is a *new* artifact: publishing it requires a new
  payload-set release and a manifest bump — published release assets are
  never replaced in place.
- **All binary inputs are official, unmodified upstream artifacts**, pinned
  by SHA-256 in `payloads/<name>/inputs.json`. The build scripts only
  *stage* files; they never patch binaries.

## General recipe (any payload)

1. Obtain the inputs listed in `payloads/<name>/inputs.json` from the
   sources named there.
2. Verify each input's SHA-256 against `inputs.json`
   (`Get-FileHash <file> -Algorithm SHA256`). Do not build from unverified
   inputs.
3. Run the payload's `build_payload.ps1` (see its header for parameters).
   It stages the layout, regenerates `SHA256SUMS.txt`, zips, and prints the
   new outer SHA-256.
4. To verify against the published release: download the published asset,
   extract both archives, and diff the two `SHA256SUMS.txt` files — all
   rows except the docs rows must be identical.
5. To publish an update: bump pins in `manifest.json` (sha256, size, url →
   new tag), commit, create the new tagged release with the zip +
   `SHA256SUMS.txt` + `manifest.json` attached, then re-download the asset
   from the manifest URL and confirm the hash round-trips.

## flir-slim (FLIR / Spinnaker slim runtime)

Inputs (full pins in [`payloads/flir-slim/inputs.json`](payloads/flir-slim/inputs.json)):

| Input | Where to get it |
|-------|-----------------|
| `spinnaker_python-4.2.0.88-cp310-cp310-win_amd64.whl` | Teledyne download portal (login required) — inside the 4.2.0.88 Python/Windows zip |
| `driver64/PGRUsb3/` (v2.7.3.640: `.inf`, `.sys`, `.cat`, `WdfCoInstaller01009.dll`) | an installed Spinnaker FULL SDK (`C:\Program Files\Teledyne\Spinnaker\driver64\PGRUsb3`) |
| `spinnaker_python-4.3.0.190-cp310-cp310-win_amd64.zip` | Teledyne download portal — source of the `licenses/` texts |
| `LGPL-2.1.txt`, `NOTICE.txt`, `README.md` | version-controlled in `payloads/flir-slim/` |

Build:

```powershell
cd payloads\flir-slim
.\build_payload.ps1 `
    -WheelPath  <path>\spinnaker_python-4.2.0.88-cp310-cp310-win_amd64.whl `
    -PySpinZip  <path>\spinnaker_python-4.3.0.190-cp310-cp310-win_amd64.zip
# default -DriverDir is the installed SDK's driver64\PGRUsb3; override if extracting elsewhere
```

Compliance note for rebuilders: the staged Teledyne files are governed by
the FLIR Spinnaker SDK License Agreement (see the payload's `NOTICE.txt`).
Rebuilding for your own use with FLIR cameras is fine; redistribution of a
rebuilt archive is subject to the same EULA terms and is the scAnt
project's call to make for its official releases only.

Validation for an official release (what v0.1.0 went through, 2026-07-21):
wheel + license files byte-identical to Teledyne originals; driver files
WHQL-signature-valid (`Get-AuthenticodeSignature` = Microsoft Windows
Hardware Compatibility Publisher); INF `[SourceDisksFiles]` references all
present; probe on an SDK-free machine (`import PySpin` →
`GetLibraryVersion()` = wheel's own version → camera enumeration); download
round-trip hash check against the manifest pin.

## The bootstrap installer

`installer/build_installer.ps1` builds `scAnt-Setup-<payloadSet>.exe` from:

1. a **scAnt_pro checkout** (private repo) — the app tree is `git archive`d
   at HEAD and pruned (legacy Hugin suite, focus-stack debug artifacts,
   internal docs); the exact commit is recorded as `APP_TREE_SHA.txt`
   inside every install, in `build/pins.iss`, and in the release notes;
2. the **payload zips** (env-lock, shinestacker; flir-slim only for the
   EULA text — no FLIR binaries are embedded), each SHA-256-verified
   against `manifest.json` (downloaded from the release, or supplied via
   `-LocalPayloadDir`);
3. **Inno Setup 7** (`ISCC.exe`).

The exe's own hash differs per build (compression timestamps) — as with
payload zips, reproducibility is **content-level**: the same scAnt_pro
commit + the same manifest payload set produce the same installed tree,
verified by the installer's §8 smoke tests. Installer releases live on the
**private scAnt_pro repo** (the exe embeds the private app tree; this
public repo carries only the installer *sources*).

### Known provenance gap

`external/focus-stack/focus-stack.exe` in the app tree is a local build:
`focus-stack 1.3-30-g953c7fa-dirty` (2024-11-14, OpenCV 4.10.0), sha256
`d9a1597a7200e728106306a408739b2487eb9d1e6ff116bac3940e3eddd236a5`.
The `-dirty` flag means locally modified sources — it is pinned here by
hash, but cannot yet be rebuilt from a public recipe. Open item: publish
the patched source / build recipe (or move to a pinned upstream release)
when focus-stack is next touched.

## Adding a new payload

1. Create `payloads/<name>/` with:
   - `build_payload.ps1` — stages pinned inputs → `SHA256SUMS.txt` → zip;
     no binary modification, fail on any missing input.
   - `inputs.json` — every input artifact with SHA-256 + acquisition source.
   - `README.md` — contents, requirements, install/uninstall, verification.
   - `NOTICE.txt` — required if anything in the payload is not plain OSS;
     staged into the archive root.
   - license texts the payload must carry (version-controlled if not
     extractable from a pinned input).
2. Add the component entry to `manifest.json` (schema per
   INSTALLER_SPEC §4 Phase B: name, version, url, sha256, size, kind, dest,
   silentArgs, licenseId, licenseUrl + any postInstall hints).
3. Follow the release steps above. One payload-set tag pins *all* current
   payloads; bumping one payload re-tags the set (assets for unchanged
   payloads can be re-attached unchanged from the previous release).
