# Releasing scAnt — local post-merge workflow

This is the process run **locally, by hand, after a pull request merges into
the `scAnt_pro` branch** of the private app repo. It is the counterpart to
[`REPRODUCING.md`](REPRODUCING.md): that document covers *rebuilding* a
payload from pinned inputs; this one covers *shipping* a release.

The process has a deliberate local/remote split:

- **Payload building (steps 3–5) is always local.** The FLIR payload inputs
  require a Teledyne portal login, and payload validation needs the reference
  machine with a camera attached.
- **The installer build (step 6) runs on GitHub Actions by default** — the
  `release-installer.yml` workflow on **scAnt_pro**, triggered by pushing the
  `installer-v*` tag. The exe is a pure function of (app commit, published
  payload set), and both inputs are reachable from CI: the app tree is the
  tagged commit, and this repo's installer sources + payloads are public. A
  local build path remains as fallback.
- **Publishing (step 8) stays a human act** in both paths: CI only ever
  creates a *draft* release, because the step-7 gate (install once from the
  actual built exe) cannot be automated on a hosted runner.

## The two-repo split

A release is **two tags in two repositories**, both named from the same
`payloadSet` version in `manifest.json`:

| Repo | Tag | Assets | Visibility |
|------|-----|--------|------------|
| `scAnt-payloads` (this one) | `v<payloadSet>` | payload zips, `SHA256SUMS.txt`, `manifest.json` | public |
| `scAnt_pro` | `installer-v<payloadSet>` | `scAnt-Setup-<payloadSet>.exe` + its SHA-256 | private |

**The installer exe is released on `scAnt_pro`, never here.** The exe embeds
the private app tree, so it cannot be published from this public repo; this
repo carries only the installer *sources* and the payloads the exe pulls.

## Step 0 — Triage: does this merge need a release?

`build_installer.ps1` prunes a lot before staging. A merge that touches only
pruned paths changes nothing in the shipped tree and needs **no release**:

| What the merge touched | Release needed? |
|---|---|
| `docs/`, `legacy_scripts/`, `tests/` | **No** — pruned from the app tree |
| Loose files in `external/` other than `exiftool.exe`, `cameraMakes.txt`, `cameraSensors.txt` | **No** — pruned |
| Untracked/ignored paths (specimen folders, scratch configs) | **No** — `git archive` only takes tracked files |
| App code, GUI, pipeline scripts, `scripts/model.yml`, `images/` | **Yes** — app-only release |
| Env spec (`conda_environment/`), shinestacker pin, focus-stack/exiftool/FLIR version | **Yes** — payload rebuild + release |
| A COLMAP/Brush upstream pin | **Yes** — manifest-only release (no payload rebuild) |

An app-only release with unchanged payload binaries is normal and has
precedent: `v0.3.0` → `v0.3.1` carry the **same** app commit (`8fd5c4f`) with
a different payload set.

## Step 1 — Preflight

```powershell
# the merge actually landed, and you are building from it
git -C C:\Users\Legos\dev\scAnt_pro fetch origin
git -C C:\Users\Legos\dev\scAnt_pro checkout scAnt_pro
git -C C:\Users\Legos\dev\scAnt_pro pull --ff-only
git -C C:\Users\Legos\dev\scAnt_pro log --oneline -5

# both trees clean — `git archive` takes HEAD, so uncommitted work is silently omitted
git -C C:\Users\Legos\dev\scAnt_pro status --short
git -C C:\Users\Legos\dev\scAnt-payloads status --short

# toolchain (ISCC only needed for the path-B local installer build)
Test-Path "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe"
gh --version; tar --version; git --version
gh auth status                                                  # needs access to both repos
```

Anything reported by `git status` that *should* ship must be committed and
merged first — the build reads `HEAD`, not the working tree.

## Step 2 — Pick the version

`payloadSet` in `manifest.json` is the single source of truth. It names the
exe (`scAnt-Setup-<payloadSet>.exe`), the payload tag (`v<payloadSet>`) and
the installer tag (`installer-v<payloadSet>`). Bump it for **every** release,
including app-only ones.

- **patch** (`0.3.1` → `0.3.2`) — app-only changes; notice/doc corrections;
  rebuilds.
- **minor** (`0.3.x` → `0.4.0`) — a payload added or removed, a component
  version bump, or a change in installer behaviour.
- **major** — `manifestVersion` schema change.

Published tags so far: payloads `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.3.1`;
installer `installer-v0.3.0`, `installer-v0.3.1`. **Next is `0.3.2`.**

## Step 3 — Rebuild payloads *(only if their inputs changed)*

Follow [`REPRODUCING.md`](REPRODUCING.md) per payload. Skip entirely for an
app-only release — unchanged zips are re-attached to the new tag as-is.

Keep the built zips in one directory; you will need them in Step 5 and can
feed them to Step 6 via `-LocalPayloadDir`.

## Step 4 — Bump the manifest

Edit `manifest.json`:

1. `payloadSet` → the new version; `updated` → today's date.
2. **Re-point every self-hosted `url` to the new tag.** This is the step most
   easily missed: five components embed the tag in their download URL and
   *all* of them must change on every bump, even when the binary is
   byte-identical —

   `focus-stack`, `flir-slim`, `env-lock`, `shinestacker`, `exiftool`

   Components with `"hostedBy": "upstream"` (`colmap-cuda`, `colmap-nocuda`,
   `brush`) point at the upstream project's own releases and must **not** be
   re-pointed.
3. For any payload rebuilt in Step 3, update its `sha256`, `size`, and
   `version`.

Sanity check that no stale tag survives:

```powershell
Select-String -Path manifest.json -Pattern "download/v" |
    ForEach-Object { $_.Line.Trim() }
```

Every line printed must carry the new tag. Then commit:

```powershell
git -C C:\Users\Legos\dev\scAnt-payloads add manifest.json
git -C C:\Users\Legos\dev\scAnt-payloads commit -m "Payload set 0.3.2: <what changed>"
git -C C:\Users\Legos\dev\scAnt-payloads push
```

## Step 5 — Publish the payload-set release (scAnt-payloads)

**Do this before Step 6.** `build_installer.ps1` resolves payload zips from
the manifest URLs, so those assets must already exist at the new tag — unless
you pass `-LocalPayloadDir`, which is the offline path for iterating.

```powershell
cd C:\Users\Legos\dev\scAnt-payloads
git tag v0.3.2
git push origin v0.3.2

gh release create v0.3.2 `
    --title "Payload set 0.3.2" `
    --notes-file <notes.md> `
    manifest.json `
    <dir>\scAnt-payload-focus-stack_1.5_win64.zip `
    <dir>\scAnt-payload-flir-slim_4.2.0.88_win64.zip `
    <dir>\scAnt-payload-env-lock_<ver>_win64.zip `
    <dir>\scAnt-payload-shinestacker_<ver>_py3-none-any.zip `
    <dir>\scAnt-payload-exiftool_13.59_win64.zip
```

Then round-trip every pin — download from the manifest URL and confirm the
hash matches, exactly as the installer will:

```powershell
$m = Get-Content manifest.json -Raw | ConvertFrom-Json
foreach ($c in $m.components | Where-Object { -not $_.hostedBy }) {
    $tmp = Join-Path $env:TEMP ([IO.Path]::GetFileName(([uri]$c.url).LocalPath))
    Invoke-WebRequest $c.url -OutFile $tmp
    $h = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    "{0,-14} {1}" -f $c.name, $(if ($h -eq $c.sha256) { "OK" } else { "MISMATCH $h" })
}
```

## Step 6 — Build the installer

### Path A — CI on scAnt_pro (default)

Push the installer tag at the merge commit you are releasing:

```powershell
cd C:\Users\Legos\dev\scAnt_pro
git tag installer-v0.3.2        # must be a commit on scAnt_pro containing
git push origin installer-v0.3.2 # .github/workflows/release-installer.yml
```

The workflow then: checks out the tagged scAnt_pro commit and this repo at
`v<payloadSet>` (version taken from the tag name), fails fast if
`manifest.json`'s `payloadSet` disagrees with the tag, installs Inno Setup,
runs `build_installer.ps1`, verifies `APP_TREE_SHA.txt` equals the tagged
commit, and creates a **draft** release `installer-v<payloadSet>` on
scAnt_pro with the exe + a `.sha256` asset and generated notes (app SHA,
payload set, component pins). It refuses to touch an already-*published*
release (rollback policy below) and replaces a stale *draft* from a failed
run.

Requires step 5 to be done first — the workflow downloads payload zips from
this repo's release at `v<payloadSet>`. A manual `workflow_dispatch` run
(input: the payload-set version) exists for rebuilding a draft without
re-tagging.

### Path B — local (offline, iteration, or CI unavailable)

```powershell
cd C:\Users\Legos\dev\scAnt-payloads\installer
.\build_installer.ps1 -ScAntRepo C:\Users\Legos\dev\scAnt_pro
# add -LocalPayloadDir <dir> to build against local zips instead of downloading
```

The script wipes and repopulates `build\`, stages the app tree via
`git archive HEAD`, prunes it, writes `APP_TREE_SHA.txt`, generates
`build\pins.iss` from the manifest, and compiles with ISCC. It prints the
output path, SHA-256 and size — **record all three**, they go in the release
notes. Make sure the checkout is at the merge commit: the local build takes
`HEAD` of whatever is checked out, unlike CI which is pinned to the tag.

Build failures (either path) are almost always one of: a payload hash that
disagrees with the manifest (Step 4 half-done), a tag whose assets are not
published yet (Step 5 skipped), or ISCC missing.

## Step 7 — Verify before publishing

**Path A**: download the exe + `.sha256` from the draft release, check the
hash matches, and confirm the notes' app SHA is the merge commit you tagged.
(The workflow has already enforced `APP_TREE_SHA` = tagged commit and
manifest/tag agreement — your job is the install test.)

**Path B**: check the build artifacts yourself:

```powershell
# the exe was built from the merge you intended
Get-Content ..\installer\build\app\APP_TREE_SHA.txt
git -C C:\Users\Legos\dev\scAnt_pro rev-parse HEAD    # must match

# pins.iss carries the new payload set and the right URLs
Get-Content ..\installer\build\pins.iss
```

Then, both paths, the §8 smoke pass — silent install on a clean VM from the
**exact asset that will ship** (path A: the draft download), confirm zero
smoke failures, and uninstall cleanly. A release that has not been installed
at least once from the actual built exe should not be published. If the FLIR
payload or the env lock changed, redo the §8.1 stages that cover it.

## Step 8 — Publish the installer release (scAnt_pro, private)

**Path A** — the draft already exists with assets and notes; publishing is:

```powershell
gh release edit installer-v0.3.2 --repo FabianPlum/scAnt_pro --draft=false
```

**Path B** — create it by hand:

```powershell
cd C:\Users\Legos\dev\scAnt_pro
git tag installer-v0.3.2
git push origin installer-v0.3.2

gh release create installer-v0.3.2 `
    --repo FabianPlum/scAnt_pro `
    --title "scAnt Setup 0.3.2" `
    --notes-file <notes.md> `
    "C:\Users\Legos\dev\scAnt-payloads\installer\Output\scAnt-Setup-0.3.2.exe"
```

Release notes must record, at minimum: the app tree commit SHA, the payload
set version, the exe SHA-256 (users need it — we ship unsigned, per D7), and
the component versions the manifest pins. (Path A generates all of this.)

## Step 9 — Post-publish

- Download the published exe, confirm its SHA-256 matches the note.
- Install once from the *published* download on a clean machine.
- If `INSTALLER_SPEC.md` §10.1 status text is now stale, update it in the app
  repo.

## Rollback

**Published assets are never replaced in place** — the installer verifies
pinned hashes, and swapping an asset under a live pin breaks every client
that already has the manifest. To correct a bad release, publish the next
patch version and mark the bad one as a pre-release (or delete the release,
keeping the tag).

## Appendix — what the exe embeds vs downloads

Embedded at build time (inside the exe): the app tree, the `env-lock`
payload, the `focus-stack` payload, the shinestacker wheel plus its LGPL
source/patches/licenses, the micromamba license, and the FLIR EULA *text*
only.

Downloaded at install time (pinned via `pins.iss`): `flir-slim`,
`colmap-cuda` / `colmap-nocuda` (GPU-gated choice), `brush`.

ExifTool ships **inside the app tree** (`external\exiftool.exe`, kept by the
prune step and smoke-tested by the installer) rather than being consumed from
its payload; the `exiftool` payload entry remains published for manifest
consumers such as the future Component Manager.
