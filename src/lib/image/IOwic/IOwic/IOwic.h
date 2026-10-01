//
// Copyright (C) 2026  Contributors to the OpenUTV Project
//
// SPDX-License-Identifier: Apache-2.0
//
#ifndef __IOwic__IOwic__h__
#define __IOwic__IOwic__h__
#include <TwkFB/FrameBuffer.h>
#include <TwkFB/IO.h>

namespace TwkFB
{

    //
    //  HEIC/HEIF writer for Windows using the Windows Imaging Component.
    //
    //  The HEVC encoder is the one the user has installed with Microsoft's
    //  "HEIF Image Extensions" and "HEVC Video Extensions"; OpenUTV ships no
    //  HEVC encoder of its own (AGENTS.md 1.4). Reading stays with IOoiio.
    //

    class IOwic : public FrameBufferIO
    {
    public:
        IOwic();
        virtual ~IOwic();

        virtual void readImage(FrameBuffer& fb, const std::string& filename, const ReadRequest& request) const;
        virtual void writeImage(const FrameBuffer& img, const std::string& filename, const WriteRequest& request) const;
        virtual std::string about() const;
        virtual void getImageInfo(const std::string& filename, FBInfo&) const;
    };

} // namespace TwkFB

#endif // __IOwic__IOwic__h__
