//
// Copyright (C) 2026  Contributors to the OpenUTV Project
//
// SPDX-License-Identifier: Apache-2.0
//
#include <RvCommon/MetalPresentationFormat.h>

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>

#include <algorithm>
#include <cctype>

namespace Rv
{
    namespace
    {
        const MetalPresentationFormat kFormats[] = {
            {MetalPresentationMode::SDR, "SDR (10-bit sRGB)", kCVPixelFormatType_ARGB2101010LEPacked, 4, GL_RGB10_A2, GL_BGRA,
             GL_UNSIGNED_INT_2_10_10_10_REV, false},
            {MetalPresentationMode::EDR, "EDR (16-bit float extended sRGB)", kCVPixelFormatType_64RGBAHalf, 8, GL_RGBA16F_ARB, GL_RGBA,
             GL_HALF_FLOAT_ARB, true},
            {MetalPresentationMode::PQ, "HDR PQ (10-bit BT.2100 PQ)", kCVPixelFormatType_ARGB2101010LEPacked, 4, GL_RGB10_A2, GL_BGRA,
             GL_UNSIGNED_INT_2_10_10_10_REV, false},
            {MetalPresentationMode::HLG, "HDR HLG (10-bit BT.2100 HLG)", kCVPixelFormatType_ARGB2101010LEPacked, 4, GL_RGB10_A2, GL_BGRA,
             GL_UNSIGNED_INT_2_10_10_10_REV, false},
        };

        CFStringRef colorSpaceName(MetalPresentationMode mode)
        {
            switch (mode)
            {
            case MetalPresentationMode::EDR:
                return kCGColorSpaceExtendedSRGB;
            case MetalPresentationMode::PQ:
                return kCGColorSpaceITUR_2100_PQ;
            case MetalPresentationMode::HLG:
                return kCGColorSpaceITUR_2100_HLG;
            case MetalPresentationMode::SDR:
            default:
                return kCGColorSpaceSRGB;
            }
        }
    } // namespace

    const MetalPresentationFormat& metalPresentationFormat(MetalPresentationMode mode)
    {
        for (const auto& format : kFormats)
        {
            if (format.mode == mode)
                return format;
        }
        return kFormats[0];
    }

    bool parseMetalPresentationMode(const std::string& text, MetalPresentationMode& mode)
    {
        std::string value(text);
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return std::tolower(c); });

        if (value == "sdr")
            mode = MetalPresentationMode::SDR;
        else if (value == "edr")
            mode = MetalPresentationMode::EDR;
        else if (value == "pq")
            mode = MetalPresentationMode::PQ;
        else if (value == "hlg")
            mode = MetalPresentationMode::HLG;
        else
            return false;
        return true;
    }

    void* createMetalPresentationSurface(int width, int height, const MetalPresentationFormat& format)
    {
        NSDictionary* props = @{
            (NSString*)kIOSurfaceWidth : @(width),
            (NSString*)kIOSurfaceHeight : @(height),
            (NSString*)kIOSurfaceBytesPerElement : @(format.bytesPerPixel),
            (NSString*)kIOSurfacePixelFormat : @(format.pixelFormat),
        };
        IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        if (!surface)
            return nullptr;

        //
        //  Tag the colorspace through CoreVideo. It writes the IOSurfaceColorSpace
        //  attachment that Core Animation reads; IOSurfaceSetValue() with a
        //  CGColorSpaceRef under kCVImageBufferCGColorSpaceKey does not.
        //
        CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(colorSpaceName(format.mode));
        CVPixelBufferRef pixelBuffer = nullptr;
        if (colorSpace && CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nullptr, &pixelBuffer) == kCVReturnSuccess)
        {
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, colorSpace, kCVAttachmentMode_ShouldPropagate);
            CVPixelBufferRelease(pixelBuffer);
        }
        if (colorSpace)
            CGColorSpaceRelease(colorSpace);

        return (void*)surface;
    }

    std::string metalSurfaceColorSpaceName(void* ioSurface)
    {
        std::string result;
        if (!ioSurface)
            return result;

        CFTypeRef value = IOSurfaceCopyValue((IOSurfaceRef)ioSurface, CFSTR("IOSurfaceColorSpace"));
        if (!value)
            return result;

        if (CGColorSpaceRef colorSpace = CGColorSpaceCreateWithPropertyList(value))
        {
            if (CFStringRef name = CGColorSpaceCopyName(colorSpace))
            {
                result = [(__bridge NSString*)name UTF8String];
                CFRelease(name);
            }
            CGColorSpaceRelease(colorSpace);
        }
        CFRelease(value);
        return result;
    }

    void metalScreenEDRHeadroom(void* nsView, double& current, double& potential)
    {
        current = 1.0;
        potential = 1.0;

        NSScreen* screen = nil;
        if (nsView)
            screen = [[(__bridge NSView*)nsView window] screen];
        if (!screen)
            screen = [NSScreen mainScreen];
        if (!screen)
            return;

        current = [screen maximumExtendedDynamicRangeColorComponentValue];
        potential = [screen maximumPotentialExtendedDynamicRangeColorComponentValue];
    }

} // namespace Rv
