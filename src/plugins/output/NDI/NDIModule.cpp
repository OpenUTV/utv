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
        const char* p_ndi_runtime_v6 = getenv(NDILIB_REDIST_FOLDER);
        if (!p_ndi_runtime_v6)
        {
            std::cout << "NDI runtime not found. Please install NDI Tools." << std::endl;
            return nullptr;
        }
        std::string ndi_path = p_ndi_runtime_v6;
        ndi_path += "\\" NDILIB_LIBRARY_NAME;
        hNDILib = LoadLibraryA(ndi_path.c_str());

        const NDIlib_v6* (*load_func)(void) = NULL;
        if (hNDILib)
            *((FARPROC*)&load_func) = GetProcAddress((HMODULE)hNDILib, "NDIlib_v6_load");
#else
        std::string ndi_path;
        const char* p_NDI_runtime_folder = getenv(NDILIB_REDIST_FOLDER);
        if (p_NDI_runtime_folder)
        {
            ndi_path = p_NDI_runtime_folder;
            ndi_path += NDILIB_LIBRARY_NAME;
        }
        else
        {
            ndi_path = NDILIB_LIBRARY_NAME;
        }
        hNDILib = dlopen(ndi_path.c_str(), RTLD_LOCAL | RTLD_LAZY);

        const NDIlib_v6* (*load_func)(void) = NULL;
        if (hNDILib)
            *((void**)&load_func) = dlsym(hNDILib, "NDIlib_v6_load");
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
            }
            std::cout << "Failed to find NDIlib_v6_load in the NDI runtime." << std::endl;
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
