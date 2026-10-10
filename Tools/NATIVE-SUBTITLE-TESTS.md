# Owned native subtitle test fixtures

Run from the Aether package root on macOS with Xcode selected and `swift`, Python 3,
`ffmpeg` (libx264 and AAC encoders), and `ffprobe` on PATH:

```sh
python3 -m unittest discover -s Tools -p 'test_native_subtitle_fixtures.py'
python3 Tools/native_subtitle_fixtures.py --check-only
python3 Tools/native_subtitle_fixtures.py
```

The last command generates fixtures, starts its own HTTP byte-range origin on an
OS-assigned `127.0.0.1` port, sets `SIGNAL_CONTAINER_TRACK_ORIGIN` for the child
`swift test --filter NativeSubtitleAutomaticSelectionTests` process, and shuts the
origin down afterward. It does not change a caller's environment or existing
origins. Tests execute serially using Swift's default XCTest behavior. Nonzero
Swift exit, a missing six-case XCTest summary, or skipped cases fails the runner.
The complete Swift output is printed for review. The package must contain the six
`NativeSubtitleAutomaticSelectionTests` cases from the shipping patch.

Every run creates a fresh temporary directory and removes it afterward. No media,
credentials, provider traffic, logs, or generated binaries belong in the fork.
Generation is bounded to 120 seconds per ffmpeg process, probing to 20 seconds per
file, and Swift build/test to 30 minutes. The generated media is about a few MB;
Swift build products are separate and may be much larger. Do not run concurrently
with another build using the same package build directory.

The three owned MKVs are 30 seconds long, safely beyond the test's 6-second seek:

| Filename | Streams |
| --- | --- |
| `owned-seek-tracks.mkv` | H.264 baseline video, English and Spanish AAC tones, one English SubRip subtitle track; subtitle default/forced/SDH all off |
| `owned-forced-sdh.mkv` | Same media, English subtitle forced and hearing-impaired flags on; default off |
| `owned.mkv` | Same video and two audio tracks; no subtitles |

The subtitle cues cover 0–10, 10–20, and 20–30 seconds. English audio is default;
Spanish audio is not. `ffprobe` checks duration, stream codecs/languages, subtitle
count, and subtitle dispositions before any native test runs. The origin exposes
only these three filenames, supports GET/HEAD and one byte range, and rejects
invalid/multiple ranges with 416. The six tests do not use diagnostic barrier
controls, so this server has no control endpoints.

`--check-only` validates fixture generation and range responses without compiling
or launching the engine. Python tests cover full/partial GET and HEAD, suffix and
open ranges, clipping, 416 responses, path allowlisting, and test-summary failure
handling. These checks do not establish native test passage. A successful full
runner establishes selection-state test passage; it does not prove visible
caption rendering, physical devices, live providers, AirPlay, or SharePlay.
