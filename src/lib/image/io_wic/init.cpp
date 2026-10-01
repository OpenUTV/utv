//
// Copyright (C) 2026  Contributors to the OpenUTV Project
//
// SPDX-License-Identifier: Apache-2.0
//
#include <IOwic/IOwic.h>
#include <iostream>

extern "C"
{

    __declspec(dllexport) TwkFB::FrameBufferIO* create();
    __declspec(dllexport) void destroy(TwkFB::IOwic*);

    TwkFB::FrameBufferIO* create() { return new TwkFB::IOwic(); }

    void destroy(TwkFB::IOwic* plug) { delete plug; }

} // extern  "C"
