# scAnt exiftool payload — ExifTool by Phil Harvey (Windows x64)

[ExifTool](https://exiftool.org) writes the camera/lens EXIF metadata into
scAnt captures (`scripts/write_meta_data.py`). This payload repackages the
**official, unmodified** Windows 64-bit distribution in the layout scAnt
expects: `exiftool.exe` (upstream ships it as `exiftool(-k).exe`; renaming
it is upstream's documented install step) next to its `exiftool_files/`
runtime directory, extracted into `external/`.

## License

ExifTool is free software by Phil Harvey, dual-licensed under the **Perl
Artistic License / GNU GPL** (same terms as Perl itself) — see
`README_upstream.txt` inside this payload and https://exiftool.org.
Source: https://github.com/exiftool/exiftool (version tag matches).
Redistribution of the unmodified distribution is permitted; this payload
only renames the exe per upstream's instructions.

## Pinned input

- `exiftool-13.59_64.zip` from the official exiftool SourceForge mirror,
  sha256 `44b512b25af500724ba579d0a53c8fc5851628b692dd5e5d94ae4a15c2cba9ec`
  (SourceForge keeps versioned files stable, unlike exiftool.org which only
  serves the current release — that's why the build pins the SF URL).

## Verify (INSTALLER_SPEC §8)

```powershell
external\exiftool.exe -ver     # expect 13.59
```

Validated 2026-07-21 against scAnt's usage: write + read round-trip of the
full `write_meta_data.py` tag set (Make, Model, SerialNumber, LensModel,
FocalLength, FocalLengthIn35mmFormat) on a real scan TIFF.

## Version note

Replaces the previous `external/exiftool.exe` 12.04 (2020, single-exe
layout). ExifTool ≥12.88 uses the exe + `exiftool_files/` layout packaged
here; scAnt resolves only the exe path, so the layout change is transparent.
