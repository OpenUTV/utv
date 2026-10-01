# Headless Rendering on Linux (Render Farms, Containers)

`utvio` (also installed as `rvio`) renders through OpenGL. On Linux it does **not** need an X server or a display: without one it creates its OpenGL context through EGL, on the GPU when the machine has one and in software otherwise.

## How the OpenGL context is chosen

| Situation | Context | Renderer |
| --- | --- | --- |
| `DISPLAY` is set (desktop, `xvfb-run`) | GLX | the X server's driver |
| No `DISPLAY`, GPU with a working driver | EGL device platform | the GPU (e.g. NVIDIA, Mesa DRM render node) |
| No `DISPLAY`, no GPU | EGL surfaceless platform | Mesa llvmpipe (software) |

If GLX fails with a display set, EGL is tried as well.

## Running on a render node

```bash
# No X server needed
utvio in.#.exr -o out.mov

# Force software rendering with no display, whatever the machine has
utvio_sw in.#.exr -o out.#.dpx        # also installed as rvio_sw
```

`utvio_sw` / `rvio_sw` replace the old OSMesa-based `rvio_sw` executable (OSMesa was removed from Mesa 25.1). They run `utvio` with `UTV_GL_PLATFORM=egl` and `LIBGL_ALWAYS_SOFTWARE=1`.

## Environment variables

| Variable | Effect |
| --- | --- |
| `UTV_GL_PLATFORM=egl` / `glx` | Force the EGL (no display) or GLX (X display) context |
| `UTV_SOFTWARE_GL=1` or `LIBGL_ALWAYS_SOFTWARE=1` | Software rendering (Mesa llvmpipe) |
| `UTV_GL_DEBUG=1` | Print which context and renderer were chosen |
| `UTV_NO_SYSTEM_GL_PRELOAD=1` | Don't preload the system `libGL`/`libEGL` in the launch wrapper |

Example:

```text
$ UTV_GL_DEBUG=1 utvio in.exr -o out.png
INFO: offscreen OpenGL context: EGL (no X display), renderer llvmpipe (LLVM 20.1.2, 128 bits)
```

## Requirements

- The system's OpenGL/EGL libraries: `libEGL.so.1` and `libGL.so.1` (libglvnd) plus a driver: either the GPU vendor's, or Mesa (`mesa-dri-drivers` on RHEL-family systems, `libgl1-mesa-dri` / `libegl1` on Debian/Ubuntu) for software rendering.
- EGL 1.5 with `EGL_EXT_platform_device` (GPU) or `EGL_MESA_platform_surfaceless` (software). Verified on Ubuntu 24.04 (Mesa 25.2), RHEL 9 compatible (Mesa 25.2) and RHEL 8 compatible (Mesa 23.1).
- In containers with an NVIDIA GPU, use the NVIDIA container runtime so the driver's EGL libraries are available.

## Troubleshooting

```text
ERROR: cannot create an offscreen OpenGL context.
ERROR:   EGL: no usable EGL device or surfaceless platform (is a GPU driver or Mesa installed?)
```

Install the Mesa packages above, or check the GPU driver's EGL support. `UTV_GL_DEBUG=1` shows what was selected.
