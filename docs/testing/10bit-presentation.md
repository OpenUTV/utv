# 10-bit Presentation Test (QOpenGLWidget spike)

This build tests whether UTV can show true 10-bit output through its plain OpenGL view, without the extra Vulkan (Windows/Linux) or Metal (macOS) presentation layer.

Background: Qt's `QOpenGLWidget` renders into an offscreen buffer that defaults to 8 bits per channel, so output was cut to 8 bits before reaching the screen. This build asks Qt for a 10-bit buffer instead.

## What you need

- A display that is set to 10-bit (or higher) output in the OS/GPU control panel. On Windows with NVIDIA, set "Output color depth: 10 bpc" in the NVIDIA Control Panel. On AMD, enable "10-bit pixel format" in Adrenalin.
- The branch build for your OS from the pull request's **Checks → Branch CI → Artifacts**.

## Setup (once)

1. Launch UTV and open **Preferences → Rendering → Display Output Format**.
2. Choose **10/10/10/2**.
3. Quit UTV.

## Run the test

Launch UTV from a terminal each time, so the log lines are visible and the environment variable applies.

Test image (a smooth horizontal ramp rendered in 32-bit float):

```text
"hramp,width=2048,height=512,depth=32f,start=1,end=1.movieproc"
```

Run each of these rows and note what you see:

| # | Environment variables | What it tests |
| --- | --- | --- |
| A | `UTV_PRESENTATION_BACKEND=gl UTV_GL_TEXTURE_FORMAT=rgba8` | Old behaviour: OpenGL view, 8-bit buffer (expect banding) |
| B | `UTV_PRESENTATION_BACKEND=gl` | **The fix**: OpenGL view, 10-bit buffer |
| C | `UTV_PRESENTATION_BACKEND=gl UTV_GL_TEXTURE_FORMAT=rgba16f` | OpenGL view, 16-bit float buffer |
| D | *(no variables)* | Current Vulkan (Win/Linux) or Metal (macOS) path, for comparison |

Examples:

```bash
# Linux / macOS
UTV_PRESENTATION_BACKEND=gl ./UTV "hramp,width=2048,height=512,depth=32f,start=1,end=1.movieproc"
```

```powershell
# Windows (PowerShell), from the install folder
$env:UTV_PRESENTATION_BACKEND = "gl"; .\utv.exe "hramp,width=2048,height=512,depth=32f,start=1,end=1.movieproc"
Remove-Item Env:UTV_PRESENTATION_BACKEND   # before the next row
```

Press `1` for 1:1 pixel scale, then look closely at the ramp. With 8 bits the ramp shows about 256 visible steps; with 10 bits it should look smooth. Row A is the "bad" reference, so compare B, C and D against it.

## What to send back

For each row:

1. Banding compared with row A: **same / less / smooth**.
2. The log lines starting with `INFO: presentation backend:` and `INFO: GL presentation:`. The second one reports the bit depth at each stage, for example:

   ```text
   INFO: GL presentation: requested display 10/10/10/2, widget texture GL_RGB10_A2, widget FBO 10/10/10/2, context 10/10/10/2, window surface 10/10/10/2
   ```

3. Any flicker, black frames, wrong colours or crashes.
4. OS version, GPU model, driver version, and the display model.

If the log lines don't appear in the terminal, they are also in the app log. UTV prints its location at startup as `INFO: File logger path: ...`.

## Expected results

- **Windows / Linux:** if row B looks as smooth as row D, the OpenGL view can do 10-bit on its own, and the Vulkan layer may not be needed for SDR 10-bit.
- **macOS:** row B will most likely still band. Qt's macOS OpenGL windows are 8-bit, which is one reason the Metal path exists (it also provides EDR/HDR).
