# Rocky Linux EPEL Packager TODO

The following VFX system dependencies are currently missing from the EPEL 9 and RPM Fusion 9 (x86_64) repositories.

To achieve a 100% native build on Rocky Linux without relying on the `vcpkg` fallback system, the community needs to build and submit the following packages to EPEL:

1. **`OpenColorIO`** (`OpenColorIO-devel`)
   - Current Status: Missing entirely from EPEL 9 (x86_64).
   - Upstream: <https://github.com/AcademySoftwareFoundation/OpenColorIO>
   - Notes: An RPM spec file likely exists in Fedora Rawhide and can be backported to EL9.

2. **`dav1d`** (`dav1d-devel`)
   - Current Status: Missing entirely from EPEL 9 and RPM Fusion 9.
   - Upstream: <https://code.videolan.org/videolan/dav1d>
   - Notes: A blazing fast AV1 decoder. Standard package name in Fedora is `dav1d-devel`.

3. **`OpenJPH`** (`openjph-devel`)
   - Current Status: Missing entirely from EPEL 9.
   - Upstream: <https://github.com/aous72/OpenJPH>
   - Notes: HTJ2K image compression library.

4. **`doctest`** (`doctest-devel`)
   - Current Status: Missing entirely from EPEL 9.
   - Upstream: <https://github.com/doctest/doctest>
   - Notes: Header-only C++ testing framework.

*Note: Once these packages are available via `dnf install`, they can be safely removed from the `vcpkg` fallback block in `build.sh`.*
