# OpenUTV Dependency Recon Report

Below is an audit of our core C++ dependencies, comparing what is natively available via system package managers (Ubuntu 24.04, EPEL 9/RPM Fusion, EPEL 10/RPM Fusion) against the latest upstream versions available from source.

## Core Libraries Version Matrix

| Library | Ubuntu 24.04 (Noble) | EPEL 9 / Rocky 9 | EPEL 10 / Rocky 10 | Latest Upstream | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **OpenImageIO** | 2.4.17.0 | 2.4.17.0 | *Not Available Yet* | **3.1.12** | ⚠️ Severely Outdated natively |
| **OpenColorIO** | 2.1.3 | *Not Available* | 2.4.2 | **2.5.1** | ⚠️ Outdated natively, missing on EL9 |
| **OpenEXR** | 3.1.5 | 3.1.1 | 3.1.10 | **3.4.11** | ⚠️ Outdated natively |
| **Imath** | 3.1.9 | 3.1.2 | 3.1.10 | **3.2.2** | 🟢 Acceptable |
| **FFmpeg** | 6.1.1 | 5.1.8 | 7.1.2 | **8.2.x** | ⚠️ EL9 severely outdated |
| **Boost** | 1.83.0 | 1.75.0 | 1.83.0 | **1.91.x** | ⚠️ EL9 severely outdated |

## Image & Media Formats

| Library | Ubuntu 24.04 (Noble) | EPEL 9 / Rocky 9 | EPEL 10 / Rocky 10 | Latest Upstream | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **libjpeg-turbo** | 2.1.5 | 2.0.90 | 3.0.2 | **3.1.x** | ⚠️ EL9 outdated |
| **libpng** | 1.6.43 | 1.6.37 | 1.6.40 | **1.6.45+** | 🟢 Acceptable |
| **libtiff** | 4.5.1 | 4.4.0 | 4.6.0 | **4.7.x** | 🟢 Acceptable |
| **libwebp** | 1.3.2 | 1.2.0 | 1.3.2 | **1.4.x** | 🟢 Acceptable |
| **LibRaw** | 0.21.2 | 0.21.1 | 0.21.3 | **0.21.3** | 🟢 Up to date |
| **dav1d** | 1.4.1 | 1.5.3 | 1.5.3 | **1.5.x** | 🟢 Up to date |
| **OpenJPH** | *Not Available* | *Not Available* | *Not Available* | **0.27.x** | ⚠️ Build from source required |

## Utilities & Others

| Library | Ubuntu 24.04 (Noble) | EPEL 9 / Rocky 9 | EPEL 10 / Rocky 10 | Latest Upstream | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **spdlog** | 1.12.0 | 1.10.0 | 1.14.1 | **1.15.x** | 🟢 Acceptable |
| **yaml-cpp** | 0.8.0 | 0.6.3 | 0.8.0 | **0.8.x** | ⚠️ EL9 outdated |
| **glew** | 2.2.0 | 2.2.0 | 2.2.0 | **2.2.0** | 🟢 Abandoned/Stable |
| **doctest** | 2.4.11 | 2.4.8 | 2.4.12 | **2.4.11** | 🟢 Acceptable |

## Key Findings & Recommendations

1. **VFX Reference Platform Sync**: Libraries like **OpenEXR**, **OpenImageIO**, and **OpenColorIO** move extremely fast and are highly interdependent in the VFX ecosystem. System package managers universally lag behind the CY2024/CY2025 VFX Reference Platforms.
2. **Rocky 9 / EPEL 9 Decay**: EL9 is showing its age. Core libraries like Boost (1.75), FFmpeg (5.1), and yaml-cpp (0.6) are heavily outdated and may soon cause compilation issues with modern C++20/C++23 features or upstream dependency conflicts.
3. **Rocky 10 / EPEL 10 Promise**: EPEL 10 (via CentOS Stream 10) provides much more modern libraries (e.g., FFmpeg 7.1, OpenColorIO 2.4, OpenEXR 3.1.10) which aligns closely with current upstream, though it is still missing some specialized packages like OpenImageIO.
4. **Way Forward**: To reliably test against "latest" dependencies across distributions, we must either:
   - **Continue building from source** (via custom scripts in `build.sh`) for the most fast-moving VFX targets (OCIO, OIIO, EXR).
   - **Re-evaluate `vcpkg`**: Despite the CMake namespace/pathing headaches it causes with native overrides, a fully managed `vcpkg` manifest ensures version lockstep across Windows, macOS, and all Linux distributions without depending on Canonical or Fedora maintainers.
