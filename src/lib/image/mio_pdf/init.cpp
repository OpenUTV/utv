//
// Copyright (C) 2026 OpenUTV Authors. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
#include <MoviePDF/MoviePDF.h>

extern "C"
{

#ifdef PLATFORM_WINDOWS
    __declspec(dllexport) TwkMovie::MovieIO* create();
    __declspec(dllexport) void destroy(TwkMovie::MoviePDFIO*);
#endif

    TwkMovie::MovieIO* create() { return new TwkMovie::MoviePDFIO(); }

    void destroy(TwkMovie::MoviePDFIO* plug) { delete plug; }

} // extern "C"
