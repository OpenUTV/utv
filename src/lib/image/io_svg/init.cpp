//
// Copyright (C) 2026  Makai Systems. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
#include <IOsvg/IOsvg.h>
#include <iostream>

extern "C"
{

#ifdef PLATFORM_WINDOWS
    __declspec(dllexport) TwkFB::FrameBufferIO* create();
    __declspec(dllexport) void destroy(TwkFB::IOsvg*);
#endif

    TwkFB::FrameBufferIO* create() { return new TwkFB::IOsvg(); }

    void destroy(TwkFB::IOsvg* plug) { delete plug; }

} // extern  "C"
