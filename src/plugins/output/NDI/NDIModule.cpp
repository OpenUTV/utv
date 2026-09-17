//
// Copyright (C) 2024  Autodesk, Inc. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#include <NDI/NDIModule.h>
#include <NDI/NDIVideoDevice.h>

#include <TwkExc/Exception.h>

#include <Processing.NDI.Lib.h>
#include <Processing.NDI.DynamicLoad.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <stdlib.h>
#include <dlfcn.h>
#endif

namespace NDI
{
    const NDIlib_v6* p_NDI_lib = nullptr;
    static void* hNDILib = nullptr;

    const NDIlib_v6* NDI_load_library()
    {
        if (p_NDI_lib)
            return p_NDI_lib;

#ifdef _WIN32
        std::vector<std::string> search_paths;
        const char* p_ndi_runtime_v6 = getenv(NDILIB_REDIST_FOLDER);
        if (p_ndi_runtime_v6 && *p_ndi_runtime_v6)
        {
            std::string p(p_ndi_runtime_v6);
            if (!p.empty() && p.back() != '\\' && p.back() != '/')
                p += "\\";
            p += NDILIB_LIBRARY_NAME;
            search_paths.push_back(p);
        }
        search_paths.push_back("C:\\Program Files\\NDI\\NDI 6 Tools\\Runtime\\" NDILIB_LIBRARY_NAME);
        search_paths.push_back("C:\\Program Files\\NDI\\NDI 6 Runtime\\v6\\" NDILIB_LIBRARY_NAME);
        search_paths.push_back("C:\\Program Files\\NDI\\NDI 6 Tools\\" NDILIB_LIBRARY_NAME);
        search_paths.push_back(NDILIB_LIBRARY_NAME);

        const NDIlib_v6* (*load_func)(void) = NULL;
        for (const auto& path : search_paths)
        {
            hNDILib = LoadLibraryA(path.c_str());
            if (hNDILib)
            {
                *((FARPROC*)&load_func) = GetProcAddress((HMODULE)hNDILib, "NDIlib_v6_load");
                if (load_func)
                    break;
                FreeLibrary((HMODULE)hNDILib);
                hNDILib = nullptr;
            }
        }
#else
        std::vector<std::string> search_paths;
        const char* p_NDI_runtime_folder = getenv(NDILIB_REDIST_FOLDER);
        if (p_NDI_runtime_folder && *p_NDI_runtime_folder)
        {
            std::string p(p_NDI_runtime_folder);
            if (!p.empty() && p.back() != '/')
                p += "/";
            p += NDILIB_LIBRARY_NAME;
            search_paths.push_back(p);
        }

#ifdef __APPLE__
        search_paths.push_back("/Library/NDI SDK for Apple/lib/macOS/" NDILIB_LIBRARY_NAME);
        search_paths.push_back("/Library/CoreMediaIO/Plug-Ins/DAL/NDIVideoOut.plugin/Contents/Frameworks/" NDILIB_LIBRARY_NAME);
        search_paths.push_back("/Applications/NDI Scan Converter.app/Contents/Frameworks/" NDILIB_LIBRARY_NAME);
        search_paths.push_back(
            "/Applications/NDI Router.app/Contents/Frameworks/NTFramework.framework/Versions/A/Frameworks/" NDILIB_LIBRARY_NAME);
        search_paths.push_back("/usr/local/lib/" NDILIB_LIBRARY_NAME);
        search_paths.push_back("/opt/homebrew/lib/" NDILIB_LIBRARY_NAME);
        search_paths.push_back(NDILIB_LIBRARY_NAME);
#else
        search_paths.push_back("/usr/lib/x86_64-linux-gnu/" NDILIB_LIBRARY_NAME);
        search_paths.push_back("/usr/lib64/" NDILIB_LIBRARY_NAME);
        search_paths.push_back("/usr/lib/" NDILIB_LIBRARY_NAME);
        search_paths.push_back("/usr/local/lib/" NDILIB_LIBRARY_NAME);
        search_paths.push_back(NDILIB_LIBRARY_NAME);
        search_paths.push_back("/usr/lib/x86_64-linux-gnu/libndi.so");
        search_paths.push_back("/usr/lib64/libndi.so");
        search_paths.push_back("/usr/lib/libndi.so");
        search_paths.push_back("/usr/local/lib/libndi.so");
        search_paths.push_back("libndi.so");
#endif

        const NDIlib_v6* (*load_func)(void) = NULL;
        for (const auto& path : search_paths)
        {
            hNDILib = dlopen(path.c_str(), RTLD_LOCAL | RTLD_LAZY);
            if (hNDILib)
            {
                *((void**)&load_func) = dlsym(hNDILib, "NDIlib_v6_load");
                if (load_func)
                    break;
                dlclose(hNDILib);
                hNDILib = nullptr;
            }
        }
#endif

        if (!load_func)
        {
            if (hNDILib)
            {
#ifdef _WIN32
                FreeLibrary((HMODULE)hNDILib);
#else
                dlclose(hNDILib);
#endif
                hNDILib = nullptr;
                // Only print if we found the library but it's an old version
                std::cout << "INFO: NDI runtime found, but it does not support v6 (NDIlib_v6_load missing). NDI disabled." << std::endl;
            }
            else
            {
                // Optional debug print for missing NDI entirely, but keeping it silent avoids spam on systems without NDI
                // std::cout << "INFO: NDI runtime (libndi) not installed. NDI disabled." << std::endl;
            }
            return nullptr;
        }
        return load_func();
    }

    NDIModule::NDIModule()
        : VideoModule()
    {
        open();

        if (!isOpen())
        {
            TWK_THROW_EXC_STREAM("Cannot run NDI");
        }
    }

    NDIModule::~NDIModule() { close(); }

    std::string NDIModule::name() const { return "NDIModule"; }

    std::string NDIModule::SDKIdentifier() const
    {
        std::ostringstream str;
        if (p_NDI_lib)
            str << "NDI SDK Version " << p_NDI_lib->version();
        else
            str << "NDI SDK Version Unknown";
        return str.str();
    }

    std::string NDIModule::SDKInfo() const { return ""; }

    void NDIModule::open()
    {
        if (isOpen())
        {
            return;
        }

        p_NDI_lib = NDI_load_library();
        if (!p_NDI_lib)
            return;

        m_NDIlib_initialized = p_NDI_lib->initialize();
        if (!m_NDIlib_initialized)
        {
            return;
        }

        NDIVideoDevice* device = new NDIVideoDevice(this, "NDIVideoDevice");
        if (device->numVideoFormats() != 0)
        {
            m_devices.push_back(device);
        }
        else
        {
            delete device;
            device = nullptr;
        }

#ifdef PLATFORM_WINDOWS
        glewInit(NULL);
#endif
    }

    void NDIModule::close()
    {
        for (const auto& device : m_devices)
        {
            delete device;
        }
        m_devices.clear();

        if (m_NDIlib_initialized)
        {
            p_NDI_lib->destroy();
            m_NDIlib_initialized = false;
        }
    }

    bool NDIModule::isOpen() const { return !m_devices.empty(); }

} // namespace NDI
