//******************************************************************************
// Copyright (c) 2026 Makai Systems and OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************
#ifndef __MovieRED__MovieREDMetal__h__
#define __MovieRED__MovieREDMetal__h__

#include <cstddef>
#include <cstdint>

namespace R3DSDK
{
    class Clip;
}

namespace TwkMovie
{
    namespace REDMetalGpu
    {
        bool isAvailable();

        bool init(const char* libPath);

        void shutdown();

        bool debayerFrame(R3DSDK::Clip* clip, size_t frameNo, uint32_t decodeMode, uint32_t pixelType, unsigned char* outBuffer,
                          size_t outBufferSize);

    } // namespace REDMetalGpu
} // namespace TwkMovie

#endif // __MovieRED__MovieREDMetal__h__
