//
// Copyright (C) 2026  Contributors to the OpenUTV Project
//
// SPDX-License-Identifier: Apache-2.0
//
//  Verifies the macOS presentation formats (SDR / EDR / PQ / HLG) end to end
//  through the same GL path QTMetalVideoDevice uses: an RGBA16F render FBO is
//  blitted into an IOSurface-backed texture and the IOSurface is read back.
//  No display is needed, so this runs headless.
//
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <RvCommon/MetalPresentationFormat.h>

#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#import <OpenGL/CGLIOSurface.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>

#include <cmath>
#include <cstring>

using namespace Rv;

namespace
{
    constexpr int kSize = 16;

    struct GLContext
    {
        CGLContextObj ctx = nullptr;

        GLContext()
        {
            // Accelerated first; the Apple software renderer on GPU-less machines.
            const CGLPixelFormatAttribute hw[] = {kCGLPFAAccelerated, kCGLPFAColorFloat, kCGLPFAColorSize, (CGLPixelFormatAttribute)64,
                                                  (CGLPixelFormatAttribute)0};
            const CGLPixelFormatAttribute sw[] = {kCGLPFARendererID, (CGLPixelFormatAttribute)kCGLRendererGenericFloatID,
                                                  (CGLPixelFormatAttribute)0};
            for (const CGLPixelFormatAttribute* attrs : {hw, sw})
            {
                CGLPixelFormatObj pf = nullptr;
                GLint count = 0;
                if (CGLChoosePixelFormat(attrs, &pf, &count) == kCGLNoError && pf)
                {
                    CGLCreateContext(pf, nullptr, &ctx);
                    CGLReleasePixelFormat(pf);
                    if (ctx)
                        break;
                }
            }
            if (ctx)
                CGLSetCurrentContext(ctx);
        }

        ~GLContext()
        {
            if (ctx)
            {
                CGLSetCurrentContext(nullptr);
                CGLDestroyContext(ctx);
            }
        }
    };

    float halfToFloat(uint16_t h) { return (float)*reinterpret_cast<__fp16*>(&h); }

    //
    //  Render `value` into an RGBA16F FBO, blit it into an IOSurface in the
    //  given presentation format (the zero-copy path in QTMetalVideoDevice),
    //  and return the red and green channels read back from the IOSurface.
    //  Returns false (with a doctest message) if the GL interop is unavailable.
    //
    bool roundTrip(const MetalPresentationFormat& format, const float value[4], float& red, float& green)
    {
        GLContext gl;
        if (!gl.ctx)
        {
            MESSAGE("no CGL context available; skipping GL round trip for ", format.name);
            return false;
        }

        IOSurfaceRef surface = (IOSurfaceRef)createMetalPresentationSurface(kSize, kSize, format);
        REQUIRE(surface != nullptr);

        GLuint surfaceTex = 0;
        glGenTextures(1, &surfaceTex);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, surfaceTex);
        const CGLError err = CGLTexImageIOSurface2D(gl.ctx, GL_TEXTURE_RECTANGLE_ARB, format.glInternalFormat, kSize, kSize, format.glFormat,
                                                    format.glType, surface, 0);
        if (err != kCGLNoError)
        {
            MESSAGE("CGLTexImageIOSurface2D unavailable (", CGLErrorString(err), "); skipping GL round trip for ", format.name);
            glDeleteTextures(1, &surfaceTex);
            CFRelease(surface);
            return false;
        }

        GLuint surfaceFbo = 0;
        glGenFramebuffersEXT(1, &surfaceFbo);
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, surfaceFbo);
        glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, surfaceTex, 0);
        CHECK(glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT) == GL_FRAMEBUFFER_COMPLETE_EXT);

        // The render FBO, as QTMetalVideoDevice allocates it.
        GLuint renderTex = 0, renderFbo = 0;
        glGenTextures(1, &renderTex);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, renderTex);
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA16F_ARB, kSize, kSize, 0, GL_RGBA, GL_FLOAT, nullptr);
        glGenFramebuffersEXT(1, &renderFbo);
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, renderFbo);
        glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, renderTex, 0);
        glViewport(0, 0, kSize, kSize);
        glClearColor(value[0], value[1], value[2], value[3]);
        glClear(GL_COLOR_BUFFER_BIT);

        glBindFramebufferEXT(GL_READ_FRAMEBUFFER_EXT, renderFbo);
        glBindFramebufferEXT(GL_DRAW_FRAMEBUFFER_EXT, surfaceFbo);
        glBlitFramebufferEXT(0, 0, kSize, kSize, 0, kSize, kSize, 0, GL_COLOR_BUFFER_BIT, GL_NEAREST);
        CHECK(glGetError() == GL_NO_ERROR);
        glFinish();

        IOSurfaceLock(surface, kIOSurfaceLockReadOnly, nullptr);
        const void* base = IOSurfaceGetBaseAddress(surface);
        if (format.pixelFormat == kCVPixelFormatType_64RGBAHalf)
        {
            const uint16_t* px = static_cast<const uint16_t*>(base);
            red = halfToFloat(px[0]);
            green = halfToFloat(px[1]);
        }
        else
        {
            uint32_t px = 0;
            std::memcpy(&px, base, sizeof(px));
            red = ((px >> 20) & 0x3FF) / 1023.0f;
            green = ((px >> 10) & 0x3FF) / 1023.0f;
        }
        IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, nullptr);

        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
        glDeleteFramebuffersEXT(1, &renderFbo);
        glDeleteFramebuffersEXT(1, &surfaceFbo);
        glDeleteTextures(1, &renderTex);
        glDeleteTextures(1, &surfaceTex);
        CFRelease(surface);
        return true;
    }
} // namespace

TEST_CASE("presentation mode names parse")
{
    MetalPresentationMode mode = MetalPresentationMode::SDR;
    CHECK(parseMetalPresentationMode("EDR", mode));
    CHECK(mode == MetalPresentationMode::EDR);
    CHECK(parseMetalPresentationMode("pq", mode));
    CHECK(mode == MetalPresentationMode::PQ);
    CHECK(parseMetalPresentationMode("hlg", mode));
    CHECK(mode == MetalPresentationMode::HLG);
    CHECK(parseMetalPresentationMode("sdr", mode));
    CHECK(mode == MetalPresentationMode::SDR);
    CHECK_FALSE(parseMetalPresentationMode("hdr10", mode));
}

TEST_CASE("presentation surfaces carry the right pixel format and colorspace")
{
    struct Expected
    {
        MetalPresentationMode mode;
        OSType pixelFormat;
        const char* colorSpace;
    };
    const Expected expected[] = {
        {MetalPresentationMode::SDR, kCVPixelFormatType_ARGB2101010LEPacked, "kCGColorSpaceSRGB"},
        {MetalPresentationMode::EDR, kCVPixelFormatType_64RGBAHalf, "kCGColorSpaceExtendedSRGB"},
        {MetalPresentationMode::PQ, kCVPixelFormatType_ARGB2101010LEPacked, "kCGColorSpaceITUR_2100_PQ"},
        {MetalPresentationMode::HLG, kCVPixelFormatType_ARGB2101010LEPacked, "kCGColorSpaceITUR_2100_HLG"},
    };

    for (const auto& e : expected)
    {
        const MetalPresentationFormat& format = metalPresentationFormat(e.mode);
        CAPTURE(format.name);
        IOSurfaceRef surface = (IOSurfaceRef)createMetalPresentationSurface(kSize, kSize, format);
        REQUIRE(surface != nullptr);
        CHECK(IOSurfaceGetPixelFormat(surface) == e.pixelFormat);
        CHECK(metalSurfaceColorSpaceName(surface) == e.colorSpace);
        CFRelease(surface);
    }
}

TEST_CASE("EDR keeps values above SDR white; SDR clips them")
{
    const float hdrValue[4] = {4.0f, 0.5f, 0.0f, 1.0f};
    float red = 0.0f, green = 0.0f;

    if (roundTrip(metalPresentationFormat(MetalPresentationMode::EDR), hdrValue, red, green))
    {
        CHECK(red == doctest::Approx(4.0f).epsilon(0.001));
        CHECK(green == doctest::Approx(0.5f).epsilon(0.001));
    }

    if (roundTrip(metalPresentationFormat(MetalPresentationMode::SDR), hdrValue, red, green))
    {
        CHECK(red == doctest::Approx(1.0f));
        CHECK(std::fabs(green - 0.5f) <= 1.0f / 1023.0f);
    }
}

TEST_CASE("PQ and HLG surfaces carry encoded [0,1] signals at 10-bit precision")
{
    const float encoded[4] = {0.75f, 0.25f, 0.0f, 1.0f};
    for (MetalPresentationMode mode : {MetalPresentationMode::PQ, MetalPresentationMode::HLG})
    {
        float red = 0.0f, green = 0.0f;
        if (roundTrip(metalPresentationFormat(mode), encoded, red, green))
        {
            CHECK(std::fabs(red - 0.75f) <= 1.0f / 1023.0f);
            CHECK(std::fabs(green - 0.25f) <= 1.0f / 1023.0f);
        }
    }
}
