# scAnt Setup for macOS and Ubuntu

The macOS (Apple Silicon) and Ubuntu (x86-64) installers, `scAnt-Setup-<payloadSet>-macos-arm64.sh` and
`scAnt-Setup-<payloadSet>-ubuntu-x86_64.sh`: self-extracting bash installers, the counterparts of the Windows
`scAnt-Setup-<payloadSet>.exe` (`../scAnt-Setup.iss`). Like the exe they are released on the private scAnt_pro repo,
because they embed the app tree; this folder holds their sources.

```bash
bash scAnt-Setup-1.0.1-macos-arm64.sh          # or: bash scAnt-Setup-1.0.1-ubuntu-x86_64.sh
bash scAnt-Setup-1.0.1-macos-arm64.sh --help   # options: components, FLIR files, silent install, install folder
```

A script run with `bash` is not subject to Gatekeeper, so the unsigned installer needs no "Open Anyway" (the
Miniforge installer works the same way). The app it creates, `~/Applications/scAnt.app`, is made on the Mac and so
carries no quarantine flag either.

### The macOS package (double-click)

`scAnt-Setup-<payloadSet>-macos-arm64.pkg` installs the same thing for people who prefer the Installer app. It is
built from the `.sh` installer by [`macos-pkg/build_pkg.sh`](macos-pkg/build_pkg.sh) and carries exactly its files:

- a per-user ("home domain") product archive: Installer offers only "Install for me only", needs no administrator
  password, and runs the postinstall as the user;
- its payload is the `.sh` installer's unpacked tree, put in `~/Library/scAnt/payload-cache/pkg-setup`; the
  postinstall ([`macos-pkg/postinstall`](macos-pkg/postinstall)) runs `setup.sh --yes` from there (its time limit is
  raised from 600 to 3600 s) and removes the tree when it is done;
- FLIR support is handled in dialogs: Teledyne's `Spinnaker-4.4.0.246.pkg` or `.dmg` is taken from Downloads (or
  Desktop) or chosen in a file dialog, Teledyne's licence from that file opens in TextEdit and must be accepted;
- at the end a dialog says whether scAnt is installed; the log is `~/Library/scAnt/install-pkg.log`;
- unattended: `installer -pkg scAnt-Setup-<v>-macos-arm64.pkg -target CurrentUserHomeDirectory` with
  `~/Library/scAnt/setup-answers.txt` holding `flir=<path to the Spinnaker pkg or dmg>` (or `flir=none`) and
  `accept-flir-license=yes`: no dialogs then;
- the uninstaller also forgets the package receipt (`pkgutil --volume "$HOME" --forget com.scant3d.scant.setup`).

The package is unsigned. A downloaded unsigned package is stopped by Gatekeeper: on macOS 15 and later, double-click
it, close the warning, then System Settings > Privacy & Security > "Open Anyway" (or, in Terminal,
`xattr -d com.apple.quarantine scAnt-Setup-<v>-macos-arm64.pkg` before opening it). The `.sh` installer avoids this.

## What it does

| | macOS | Ubuntu |
|---|---|---|
| install folder (no administrator rights) | `~/Library/scAnt` | `~/.local/share/scAnt` |
| launcher | `~/Applications/scAnt.app` (bundle id `com.scant3d.scant`, ad hoc signed; console in `~/Library/Logs/scAnt/scAnt.log`) | menu entry `~/.local/share/applications/scant.desktop`; console in `~/.local/state/scAnt/scAnt.log` |
| Python | micromamba creates `env/` from the explicit lock, then the hash-pinned pip layer and the shinestacker wheel, all `--no-deps` | the same |
| focus-stack | `focus-stack.app` | the AppImage, extracted (no FUSE needed) |
| ExifTool 13.59 | conda-forge's, in the environment | the same |
| COLMAP 4.2.1 | upstream `COLMAP.app` (macOS 15+), downloaded | conda-forge, CPU or CUDA 12.9 build, in `tools/colmap` |
| Brush 0.3.0 | upstream, downloaded | upstream, downloaded |
| FLIR camera support | from the customer's `Spinnaker-4.4.0.246.pkg` (or its `.dmg`): unpacked with `pkgutil`, not installed; Teledyne's libraries go unmodified to `flir/lib` and are found through `DYLD_FALLBACK_LIBRARY_PATH` (`DYLD_LIBRARY_PATH` if Teledyne's or Homebrew's copies are on the Mac); scAnt's LGPL ffmpeg 6 for libSpinVideo; PySpin from the pkg's `pyspin-310` component | PySpin from the customer's `spinnaker_python-4.4.0.246-cp310-cp310-linux_x86_64.tar.gz`; the SDK itself in `/opt/spinnaker` by Teledyne's `install_spinnaker.sh` from the customer's SDK tarball, which the installer runs in its system setup |
| FLIR licence | Teledyne's licence text is shown from the customer's files and must be accepted (typed `accept`, or `--accept-flir-license`); a copy goes to `flir/licenses`; `~/.config/spinnaker/privacy.xml` opts out of Spinnaker's analytics unless the user has one | the same |
| needs sudo | nothing | optional system setup: the `dialout` group, a udev rule that keeps ModemManager off the controller (USB 1d50:6029), and for FLIR Ubuntu's ffmpeg/libusb packages plus Teledyne's installer (its udev rule, USB-FS memory) |
| checks | `bin/scant-check` (written to `install-smoke.log`): the environment's imports, pip check, Qt, shinestacker without Qt 6, the masking model, ExifTool, focus-stack, rig_stack's library, the version, PySpin with the camera count, COLMAP, Brush | the same |
| uninstall | `~/Library/scAnt/uninstall.sh` (keeps files you made in the app folder) | `~/.local/share/scAnt/uninstall.sh` |

Re-running the installer repairs or adds components; it re-creates the Python environment only when its lock
changed (or with `--repair`).

Teledyne's Ubuntu packages ask their questions (licence, analytics) through debconf, and their preinst stops when it
cannot show one (`db_input` under `set -e`). So the step that runs Teledyne's `install_spinnaker.sh` needs a
terminal, also in a `--yes` install; with `--accept-flir-license` the licence question is answered in advance.

The installers use the scAnt_pro commit of the Windows release unchanged. On Linux, scAnt 1.0.0 looks for
`SPLAT/external/colmap/bin/colmap.exe` and `SPLAT/external/brush/brush_app.exe`; the installer adds those names as
links to the real programs.

## Building

```bash
# rig_stack's library, built from the release commit's native sources:
#   macOS: in a scAnt_pro checkout, MACOSX_DEPLOYMENT_TARGET=14.0 python -m scripts.rigstack build, then the
#          bit_identity harness (scripts/rigstack/native/README.md)
#   Linux: the rigstack-native workflow's ubuntu-22.04 artifact (scant_stack-linux-x64-glibc2.35) of that commit
installer/unix/build_installer.sh --platform macos-arm64 --scant-repo <scAnt_pro> --ref <release commit> \
    --rigstack-dir <folder with libscant_stack.dylib + scant_stack.json> [--payload-dir <local payloads>]
installer/unix/build_installer.sh --platform linux-x86_64 --scant-repo <scAnt_pro> --ref <release commit> \
    --rigstack-dir <folder with libscant_stack.so + scant_stack.json> [--payload-dir <local payloads>]
```

The build checks every payload against `manifest-<platform>.json` and its own `SHA256SUMS.txt`, the library
against its `scant_stack.json` and the commit's source digest, and the firmware builds against
`firmware/skr/manifest.json`; it prunes the app tree like `build_installer.ps1` (Windows tools, docs, tests, closed
sources) and writes `APP_TREE_SHA.txt`. It prints the installer's SHA-256 and writes `<installer>.sha256`.
The payloads come from `../../payloads/build_unix_payloads.sh` (see `../../REPRODUCING.md`).
