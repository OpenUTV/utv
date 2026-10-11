# UTV test media generator

`utv_testmedia.py` builds synthetic test media on demand, so nobody has to keep a folder of sample files around. It
covers codecs and containers, image formats, EXR features, large files for playback performance, and deliberately
corrupted files for robustness testing. Every recipe is deterministic: the same recipe and parameters always produce
the same pixels.

## Requirements

- Python 3.11 or later (standard library only)
- `ffmpeg` and `ffprobe` on `PATH`, for movies and most image sequences
- `oiiotool` (OpenImageIO) on `PATH`, for EXR and the formats ffmpeg cannot write
- Optional: the `OpenEXR` and `numpy` Python modules, for EXR compressions newer than oiiotool supports (HTJ2K, ZSTD)

On macOS, `brew install ffmpeg openimageio` covers everything except the optional modules. Recipes whose tools are
missing are listed but skipped; `doctor` shows what is missing and how to get it.

## Usage

```sh
python3 scripts/testmedia/utv_testmedia.py doctor            # tools found, recipes buildable here
python3 scripts/testmedia/utv_testmedia.py list              # every recipe and tag
python3 scripts/testmedia/utv_testmedia.py list -v -t exr    # EXR recipes with their tags and requirements

python3 scripts/testmedia/utv_testmedia.py gen -t smoke      # a quick cross-section of formats
python3 scripts/testmedia/utv_testmedia.py gen 'prores-*' exr-multilayer
python3 scripts/testmedia/utv_testmedia.py gen -t perf -x movie

# Open a generated item in UTV
utv "$(python3 scripts/testmedia/utv_testmedia.py path exr-multilayer)"
```

Output goes to `~/.cache/utv-testmedia` (`%LOCALAPPDATA%\utv-testmedia` on Windows). Set `UTV_TESTMEDIA_DIR` or pass
`-o DIR` (before the command) to put it elsewhere. Each recipe gets its own folder containing the media and a
`meta.json`; `gen` also writes `manifest.json` listing everything generated, for test harnesses to read.

Generation is cached. Running `gen` again skips recipes whose output is up to date; `-f` rebuilds them. Delete the
output folder to reclaim the space. The performance recipes are large (the 6K PNG sequence alone is about 3 GB).

### Changing parameters

Every recipe accepts `--res WxH`, `--fps`, `--frames`, `--start` (first frame number for sequences, default 1001),
`--seed`, `--pattern` and `--audio`. `--set KEY=VALUE` overrides any other recipe parameter shown by `list --json`.
Overridden builds go in a folder with a hash suffix, so they never replace the default build.

```sh
python3 scripts/testmedia/utv_testmedia.py gen 'exr-half-*' --res 3840x2160 --frames 48
python3 scripts/testmedia/utv_testmedia.py gen h264-mp4 --fps 59.94 --audio 5.1 --set gop=1
```

Picture patterns: `counter` (colour bars with a large frame number), `motion` (moving shapes), `bars` (SMPTE HD bars),
`grain` (motion with per-frame noise, so files compress like real footage) and `gradient` (smooth ramps that show
banding). Audio layouts: `none`, `mono`, `stereo`, `5.1` and `7.1`, with a different tone on each channel and a beep
every second for checking sync.

## What is covered

| Tag | Contents |
| --- | --- |
| `movie`, `codec` | H.264, HEVC (including HDR10 PQ and HLG), ProRes 422 Proxy to 4444 XQ, DNxHR LB to 444, DNxHD, CineForm, AV1, VP9, MPEG-2, Motion JPEG, FFV1, JPEG 2000, QuickTime Animation, v210, PNG-in-MOV |
| `edge` | Odd dimensions, anamorphic pixels, rotation metadata, variable frame rate, interlacing, timecode tracks, multiple and multichannel audio tracks, full-range video |
| `sequence`, `format` | PNG 8/16-bit, DPX 10/12/16-bit, TIFF 8/16-bit, half and float, JPEG, JPEG XL, WebP, Targa, SGI, BMP, Radiance HDR |
| `exr` | Every compression type (including HTJ2K and ZSTD), half and float, render layers with mixed half, float and uint channels, multi-part, multi-part with a smaller data window, tiled and mip-mapped, overscan and cropped data windows, luminance-only, stereo multi-view, deep |
| `naming` | Frame padding variants, negative frame numbers, single-frame sequences, Unicode and spaces in paths |
| `perf` | 6K PNG, 4K DPX, 4K EXR (DWAA, PIZ, float, render layers), 4K H.264 at 60 fps, 4K HEVC, 4K ProRes HQ, 4K DNxHR HQX, and a long-GOP H.264 for scrubbing |
| `corrupt` | Truncated files, missing MP4 index, bit errors, zeroed ranges, garbage headers, empty files, EXR and DPX headers claiming enormous images, bad EXR offset tables, PNG CRC errors, missing frames, a frame in the wrong format, a frame at the wrong resolution |

`smoke` marks a small set worth running on every change.

## Checking UTV against the media

`check` decodes every generated item with `utvio`, at one eighth size, and reports the result:

```sh
python3 scripts/testmedia/utv_testmedia.py gen -t corrupt
python3 scripts/testmedia/utv_testmedia.py check -t corrupt
python3 scripts/testmedia/utv_testmedia.py check --bin-dir _build/stage/app/UTV.app/Contents/MacOS -x perf
```

For a clean recipe, `ok` means every expected frame decoded. For a `corrupt` recipe, `ok` or `rejected` are both
passes: UTV may refuse damaged media, but `CRASH` or `HANG` is always a failure. The exit code is non-zero when anything
fails. By default `check` uses the installed UTV; `--bin-dir` points it at a build.

## Corrupting any file

The byte-level damage used by the `corrupt` recipes also works on any file. The input is never modified.

```sh
python3 scripts/testmedia/utv_testmedia.py corrupt shot.mov broken.mov --op bitflip --count 500 --seed 7
python3 scripts/testmedia/utv_testmedia.py corrupt shot.mov cut.mov --op truncate --fraction 0.3
```

Operations: `truncate`, `bitflip`, `zero`, `garbage` and `empty`; see `corrupt --help`.

## Adding a recipe

Recipes live in `testmedia/`: `video.py` (movies), `sequences.py` (image sequences other than EXR), `exr.py` and
`corrupt.py`. A recipe is a function decorated with `@recipe`, which takes a name, a one-line description, tags, the
tools it needs and its default parameters, and returns a `Result` naming the file or sequence to open:

```python
@recipe(
    "h264-intra-mp4",
    "H.264 all-intra (GOP 1), so every frame is a keyframe",
    tags=("movie", "codec", "h264", "mp4"),
    needs=(FFMPEG, ffmpeg_encoder("libx264")),
    pattern="counter",
    audio="stereo",
)
def h264_intra(ctx, p, outdir):
    return encode(ctx, p, outdir, "mp4", H264 + ["-g", "1", "-bf", "0"], "yuv420p")
```

Write output only inside `outdir`; the build happens in a staging folder that replaces the cached one on success.
When a recipe's output changes, pass a higher `rev=` so existing caches are rebuilt. For a new kind of damage, add a
function to `corrupt.py` and register it with `file_corruption()` or `frame_corruption()` on top of a clean recipe.
