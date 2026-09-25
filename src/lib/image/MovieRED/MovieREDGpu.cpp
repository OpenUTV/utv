//******************************************************************************
// Copyright (c) 2026 Makai Systems and OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#include <MovieRED/MovieREDGpu.h>
#if defined(__APPLE__)
#include <MovieRED/MovieREDMetal.h>
#endif
#include <MovieRED/MovieREDOpenCL.h>

namespace TwkMovie
{
    namespace REDGpu
    {
        bool isAvailable()
        {
#if defined(__APPLE__)
            if (REDMetalGpu::isAvailable())
                return true;
#endif
            return REDOpenCLGpu::isAvailable();
        }

        bool init(const char* libPath)
        {
#if defined(__APPLE__)
            if (REDMetalGpu::init(libPath))
                return true;
#endif
            return REDOpenCLGpu::init(libPath);
        }

        void shutdown()
        {
#if defined(__APPLE__)
            REDMetalGpu::shutdown();
#endif
            REDOpenCLGpu::shutdown();
        }

        bool debayerFrame(R3DSDK::Clip* clip, size_t frameNo, uint32_t decodeMode, uint32_t pixelType, unsigned char* outBuffer,
                          size_t outBufferSize, R3DSDK::Metadata* outFrameMetadata)
        {
#if defined(__APPLE__)
            if (REDMetalGpu::isAvailable())
            {
                return REDMetalGpu::debayerFrame(clip, frameNo, decodeMode, pixelType, outBuffer, outBufferSize, outFrameMetadata);
            }
#endif
            if (REDOpenCLGpu::isAvailable())
            {
                return REDOpenCLGpu::debayerFrame(clip, frameNo, decodeMode, pixelType, outBuffer, outBufferSize, outFrameMetadata);
            }
            return false;
        }

        const char* backendName()
        {
#if defined(__APPLE__)
            if (REDMetalGpu::isAvailable())
                return "Metal";
#endif
            if (REDOpenCLGpu::isAvailable())
                return "OpenCL";
            return "None";
        }
    } // namespace REDGpu
} // namespace TwkMovie
