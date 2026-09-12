//******************************************************************************
// Copyright (c) 2026 OpenUTV / Makai Systems
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//******************************************************************************

#ifndef __MovieFFMpeg__AVFProResRawReader__h__
#define __MovieFFMpeg__AVFProResRawReader__h__

#include <string>
#include <cstdint>
#include <cstddef>

namespace TwkMovie
{

    class AVFProResRawReader
    {
    public:
        AVFProResRawReader();
        ~AVFProResRawReader();

        bool open(const std::string& filepath, int trackIndex = 0, double fps = 0.0);
        void close();

        const std::string& filePath() const;
        int width() const;
        int height() const;
        int64_t totalFrames() const;
        double fps() const;

        // Reads frame at 0-based frameIndex into dst as 8-bit RGBA pixels.
        bool readFrame(int64_t frameIndex, uint8_t* dst, size_t rowBytes, int outWidth, int outHeight);

    private:
        struct Impl;
        Impl* m_impl;
    };

} // namespace TwkMovie

#endif // __MovieFFMpeg__AVFProResRawReader__h__
