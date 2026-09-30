//
// Copyright (C) 2026  Contributors to the OpenUTV Project
//
// SPDX-License-Identifier: Apache-2.0
//
#ifndef __RvCommon__MetalPresentationFormat__h__
#define __RvCommon__MetalPresentationFormat__h__

#include <cstdint>
#include <string>

namespace Rv
{
    //
    //  How finished frames are handed to the macOS compositor.
    //
    //  The renderer always draws into an RGBA16F FBO. The presentation mode
    //  picks the IOSurface pixel format that frame is copied into and the
    //  colorspace the IOSurface is tagged with, which tells Core Animation how
    //  to interpret the values:
    //
    //  SDR  10-bit unorm, sRGB. Values are clipped to [0,1]. The default.
    //  EDR  16-bit float, extended sRGB. The display pipeline's sRGB-encoded
    //       output passes through unchanged, so SDR content looks the same;
    //       values above 1.0 are brighter than SDR white and use the display's
    //       EDR headroom.
    //  PQ   10-bit unorm, ITU-R BT.2100 PQ. Expects PQ-encoded Rec.2020 output
    //       (display colorspace SMPTE 2084 or an OCIO PQ view); macOS maps it
    //       into the display's headroom.
    //  HLG  10-bit unorm, ITU-R BT.2100 HLG.
    //
    //  Qt-free so it can be exercised by a standalone test.
    //

    enum class MetalPresentationMode
    {
        SDR,
        EDR,
        PQ,
        HLG
    };

    struct MetalPresentationFormat
    {
        MetalPresentationMode mode;
        const char* name;
        uint32_t pixelFormat; // kCVPixelFormatType_*
        int bytesPerPixel;
        unsigned int glInternalFormat; // for CGLTexImageIOSurface2D / GLFBO
        unsigned int glFormat;         // glReadPixels / CGLTexImageIOSurface2D format
        unsigned int glType;           // glReadPixels / CGLTexImageIOSurface2D type
        bool extendedRange;            // values above 1.0 survive
    };

    const MetalPresentationFormat& metalPresentationFormat(MetalPresentationMode mode);

    // Parses "sdr", "edr", "pq" or "hlg" (case-insensitive).
    bool parseMetalPresentationMode(const std::string& text, MetalPresentationMode& mode);

    // Creates an IOSurface (an IOSurfaceRef the caller releases) in the format's pixel format,
    // tagged with its colorspace. Returns nullptr on failure.
    void* createMetalPresentationSurface(int width, int height, const MetalPresentationFormat& format);

    // Name of the colorspace an IOSurface is tagged with (e.g. "kCGColorSpaceExtendedSRGB"),
    // or an empty string when it has none. Used for logging and tests.
    std::string metalSurfaceColorSpaceName(void* ioSurface);

    // EDR headroom (maximum color component value) of the screen showing nsView, or of the
    // main screen when nsView is null. "current" is what macOS grants right now; "potential"
    // is the most the display can provide. Both are 1.0 on displays without EDR.
    void metalScreenEDRHeadroom(void* nsView, double& current, double& potential);

} // namespace Rv

#endif // __RvCommon__MetalPresentationFormat__h__
