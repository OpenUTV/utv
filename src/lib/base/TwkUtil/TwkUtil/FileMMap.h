//******************************************************************************
// Copyright (c) 2008 Tweak Inc.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************
#ifndef __TwkUtil__FileMMap__h__
#define __TwkUtil__FileMMap__h__

#include <string>
#ifdef WIN32
#include <cstdint>
#define ssize_t long
#else
#include <sys/mman.h>
#include <sys/types.h>
#endif

#include <TwkUtil/dll_defs.h>

namespace TwkUtil
{

    ///
    /// This struct is just a simple way to make a memory mapped file for
    /// reading without worrying about exception safety. After
    /// constructed, the rawdata field will have a pointer to the
    /// beginning of the memory mapped region. The file is mapped
    /// READONLY.
    ///
    /// The unmap happens in the destructor.
    ///

#ifndef WIN32

    struct TWKUTIL_EXPORT FileMMap
    {
        FileMMap(const std::string& filename, bool reallyMMap = false);
        ~FileMMap();

        void* rawdata;
        ssize_t fileSize;

        int file;
        bool deleteData;
    };

#else

    struct TWKUTIL_EXPORT FileMMap
    {
        FileMMap(const std::string& filename, bool reallyMMap = true);
        ~FileMMap();

        void* rawdata;
        ssize_t fileSize;

        intptr_t fileHandle;
        intptr_t mapHandle;

        bool deleteData;
    };

#endif

} // namespace TwkUtil

#endif // __TwkUtil__FileMMap__h__
