# ffmpeg-spinvideo 6.1.6 (macOS, Apple Silicon)

A minimal shared FFmpeg 6.1.6 for Teledyne's `libSpinVideo` on macOS, which links Homebrew's `ffmpeg@6` libraries
(`libavcodec.60`, `libavformat.60`, `libavutil.58`, `libswscale.7`, `libswresample.4`). PySpin loads libSpinVideo, so
these libraries must be found, although scAnt never records video. The macOS installer puts them in
`<install>/flir/lib` next to the Spinnaker libraries it unpacks from the customer's own `Spinnaker-4.4.0.246.pkg`.

- **Licence:** LGPL-2.1-or-later. Configured without `--enable-gpl` and `--enable-nonfree`; `configure_line.txt` has the
  exact line. The corresponding source is the official `ffmpeg-6.1.6.tar.xz`
  (SHA-256 `d4fcb164028dd3beee5d92c0ac72e46aac6973c75ea12dc14de07bf8f407370a`), attached unchanged to the same
  scAnt-payloads release; the build recipe is `build_ffmpeg.sh` here.
- **Components:** encoders rawvideo, mjpeg and mpeg4, muxers avi and mp4, the file protocol; no autodetected system
  libraries. `MACOSX_DEPLOYMENT_TARGET=14.0`.
- **Install names:** `@loader_path/<leaf>`, so the libraries find each other in their folder; Teledyne's binaries are
  not modified (dyld finds these by leaf name through `DYLD_FALLBACK_LIBRARY_PATH` or `DYLD_LIBRARY_PATH`, set by the
  scAnt launcher).
- **Re-exports:** under the two-level namespace each symbol libSpinVideo imports is bound to one ffmpeg library.
  `build_ffmpeg.sh` checks this with `spinvideo_unresolved.py` (the check of scAnt_pro's
  `scripts/macos/setup_spinnaker_macos.sh`) and rebuilds with `-Wl,-u,_av_image_alloc,-u,_av_image_get_buffer_size`,
  so libavcodec re-exports the two libavutil symbols libSpinVideo expects there.

Build (a Mac with the Command Line Tools):

```bash
./build_ffmpeg.sh ffmpeg-6.1.6.tar.xz <expanded pkg>/Spinnaker-4.4.0.246-libraries.pkg/Payload/usr/local/lib/libSpinVideo.4.4.0.246.dylib build out
FFMPEG_BUILD=out ../build_unix_payloads.sh macos-arm64 dist
```

Two builds on the same machine are not byte-identical (the content-level reproducibility of REPRODUCING.md applies).

Verified 2026-11-19 on macOS 27.2 with a Blackfly S BFS-U3-200S6C: PySpin 4.4.0.246 loads and lists the camera with
these libraries and the unmodified Teledyne libraries.
