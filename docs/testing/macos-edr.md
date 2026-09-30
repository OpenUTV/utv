# macOS EDR / HDR Presentation Test

UTV can hand frames to macOS as SDR (default), EDR, HDR PQ or HDR HLG.

- **EDR** (extended dynamic range): values above SDR white (1.0) are shown brighter, up to the display's headroom. SDR content looks the same as in SDR mode.
- **HDR PQ / HLG**: the display pipeline outputs PQ or HLG encoded Rec.2020 (display colorspace SMPTE 2084 / HLG, or an OCIO HDR view such as ACES 2.0 Rec.2100-PQ), and macOS maps it into the display's headroom.

You don't need an HDR monitor. Most Apple Silicon Mac built-in displays have EDR headroom (typically 2×; XDR displays up to 16×). UTV logs the headroom when an HDR mode is active.

## Select a mode

**Preferences → Rendering → macOS Presentation**, then restart UTV.

Or, for a single launch from Terminal (overrides the preference):

```bash
UTV_MACOS_PRESENTATION=edr /Applications/UTV.app/Contents/MacOS/UTV
```

Valid values: `sdr`, `edr`, `pq`, `hlg`.

## Quick EDR check

Launch three tiles at 1×, 2× and 4× SDR white:

```bash
UTV_MACOS_PRESENTATION=edr /Applications/UTV.app/Contents/MacOS/UTV -tile \
  "solid,red=1,green=1,blue=1,depth=32f,width=640,height=360,start=1,end=1.movieproc" \
  "solid,red=2,green=2,blue=2,depth=32f,width=640,height=360,start=1,end=1.movieproc" \
  "solid,red=4,green=4,blue=4,depth=32f,width=640,height=360,start=1,end=1.movieproc"
```

Expected:

| Mode | 1× tile | 2× tile | 4× tile |
| --- | --- | --- | --- |
| `sdr` | white | same white | same white |
| `edr` on a 2× headroom display | white | visibly brighter | same as 2× (display limit) |
| `edr` on an XDR display | white | brighter | brighter still |

The terminal shows lines like:

```text
INFO: [MetalView] presentation format: EDR (16-bit float extended sRGB) (UTV_MACOS_PRESENTATION)
INFO: [MetalView] display EDR headroom: current 1x, potential 2x
```

`potential 1x` means the display has no EDR headroom, so highlights will clip.

Real HDR media works the same way: open a float EXR with values above 1.0 in `edr` mode, and highlights above SDR white use the display's headroom.

Notes:

- EDR headroom shrinks as screen brightness goes up (at maximum brightness a non-XDR display may have none); turn the brightness down a few steps if the 2× tile doesn't look brighter.
- Screenshots don't capture EDR brightness reliably; compare by eye.
