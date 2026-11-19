# focus-stack 1.5 for macOS and Ubuntu

PetteriAimonen/focus-stack release 1.5, unmodified (MIT, `LICENSE.md` from the tag). The binary reports
`1.3-42-g0cd289e`, the same build as the Windows payload's `focus-stack.exe`.

| Payload | Upstream asset (SHA-256) | Installed as |
|---|---|---|
| `scAnt-payload-focus-stack_1.5_macos-arm64.tar.gz` | `focus-stack_MacOSX.zip` (`332b0667c0edd92c75c37b56476c46ca2aa729bb2aa63476bb5704776300ea96`), its `focus-stack.app` | `app/external/focus-stack/focus-stack.app` |
| `scAnt-payload-focus-stack_1.5_linux-x86_64.tar.gz` | `focus-stack.AppImage` (`97740c829bbd1d9f873c09694a58f22944c9ec8237d3a30360877960b3bff865`) | extracted (`--appimage-extract`) to `app/external/focus-stack/squashfs-root/`; `focus-stack.AppImage` there is a two-line script that runs it, so it needs no FUSE |

The macOS bundle is ad hoc signed upstream (its GUI's seal is broken upstream; the command-line tool scAnt runs
verifies). The tar.gz is made without macOS metadata, which keeps the bundle's symlinks and signature intact.
