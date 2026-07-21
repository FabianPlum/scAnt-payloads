# scAnt-payloads

Binary payload hosting for the [scAnt](https://github.com/FabianPlum/scAnt_pro)
unified installer. The installer downloads pinned, SHA-256-verified payloads
from the tagged releases of this repository; this repo's git tree holds only
the **manifest**, per-payload **documentation/notices**, and the
**reproducible build scripts** — the binaries themselves live in
[Releases](../../releases).

## How it works

- Each release tag (`v0.1.0`, `v0.2.0`, …) is a **payload set**: a
  `manifest.json` plus the payload archives it pins.
- [`manifest.json`](manifest.json) records, per component:
  `name, version, url, sha256, size, kind, dest, silentArgs, licenseId,
  licenseUrl` — the scAnt bootstrap installer (and later the scAnt Component
  Manager) consumes this manifest unchanged.
- Updating a component = rebuild its payload, bump its pin in the manifest,
  tag a new payload-set release. Nothing here is mutable in place.

## Payloads

| Payload | Version | Contents | License |
|---------|---------|----------|---------|
| [`flir-slim`](payloads/flir-slim/) | 4.2.0.88 (driver 2.7.3.640) | PySpin wheel (self-contained Spinnaker runtime) + WHQL-signed USB3 kernel driver + license texts | **proprietary — FLIR Spinnaker SDK License Agreement** |
| [`env-lock`](payloads/env-lock/) | 2026.07.21 (micromamba 2.8.1-0) | micromamba + conda-lock/explicit lockfiles for the audited `scAnt_pro` env (win-64; conda packages stream from conda-forge at install time) | BSD-3-Clause (micromamba); lockfiles MIT |

More phase-1 payloads (shinestacker wheel, conda-lock, …) will be added one
by one; upstream-hosted tools (COLMAP, Brush) are downloaded by the installer
directly from their official releases and are *not* mirrored here.

## Licensing

The scripts and documentation **in this repository** are MIT-licensed (see
[LICENSE](LICENSE)). The **release assets are not**: each payload carries its
own license terms, documented in its `NOTICE.txt` inside the archive and
under [`payloads/<name>/`](payloads/) here.

In particular, the `flir-slim` payload contains proprietary Teledyne FLIR
Spinnaker(R) components, redistributed as part of the scAnt scanner product
under the OEM provisions of Section 4 of the FLIR Spinnaker SDK License
Agreement. Downloading and using it means accepting that agreement:
**use only with FLIR cameras you own; no further redistribution.**
The scAnt installer shows this EULA and requires explicit acceptance before
fetching the payload.

FLIR(R) and Spinnaker(R) are trademarks of Teledyne FLIR LLC. scAnt is not
affiliated with or endorsed by Teledyne FLIR. All names are used for
identification purposes only.

## Rebuilding a payload

See [REPRODUCING.md](REPRODUCING.md) for the full process. Short version:
each payload directory contains a `build_payload.ps1` plus an `inputs.json`
pinning every upstream input by SHA-256; builds are content-reproducible
(verified via the in-archive `SHA256SUMS.txt` — outer zip hashes differ per
rebuild and are pinned in `manifest.json` per release).
