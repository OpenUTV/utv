//******************************************************************************
// Copyright (c) 2026 Makai Systems and OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#ifndef __MovieRED__MovieREDGpu__h__
#define __MovieRED__MovieREDGpu__h__

#include <cstddef>
#include <cstdint>

namespace R3DSDK
{
    class Clip;
    class Metadata;
} // namespace R3DSDK

namespace TwkMovie
{
    namespace REDGpu
    {
        bool isAvailable();
        bool init(const char* libPath);
        void shutdown();
        bool debayerFrame(R3DSDK::Clip* clip, size_t frameNo, uint32_t decodeMode, uint32_t pixelType, unsigned char* outBuffer,
                          size_t outBufferSize, R3DSDK::Metadata* outFrameMetadata = nullptr);
        const char* backendName();
    } // namespace REDGpu
} // namespace TwkMovie

#endif // __MovieRED__MovieREDGpu__h__
