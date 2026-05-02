# Rocky Linux EPEL Packager TODO

The following VFX system dependencies are currently missing from the EPEL 9 and RPM Fusion 9 (x86_64) repositories.

To achieve a 100% native build on Rocky Linux without relying on the `vcpkg` fallback system, the community needs to build and submit the following packages to EPEL:

1. **`OpenColorIO`** (`OpenColorIO-devel`)
   - Current Status: Missing entirely from EPEL 9 (x86_64).
   - Upstream: <https://github.com/AcademySoftwareFoundation/OpenColorIO>
   - Notes: An RPM spec file likely exists in Fedora Rawhide and can be backported to EL9.

*Note: Once these packages are available via `dnf install`, they can be safely removed from the `vcpkg` fallback block in `build.sh`.*
