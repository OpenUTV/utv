//
// Copyright (C) 2026  Makai Systems. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
#pragma once

#include <TwkFB/FrameBuffer.h>
#include <TwkFB/IO.h>
#include <string>

namespace TwkFB
{

    class IOsvg : public FrameBufferIO
    {
    public:
        IOsvg();
        virtual ~IOsvg();

        virtual void getImageInfo(const std::string& filename, FBInfo& fbi) const override;
        virtual void readImage(FrameBuffer& fb, const std::string& filename, const ReadRequest& request) const override;
        virtual std::string about() const override;
    };

} // namespace TwkFB
