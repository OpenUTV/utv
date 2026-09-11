//******************************************************************************
// Copyright (c) 2026 OpenUTV / Makai Systems
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//******************************************************************************

#include "AVFProResRawReader.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <Accelerate/Accelerate.h>
#include <iostream>
#include <cmath>

namespace TwkMovie
{

struct AVFProResRawReader::Impl
{
    std::string filePath;
    int trackIndex{0};
    int width{0};
    int height{0};
    double fps{24.0};
    int64_t totalFrames{0};
    CMTime minFrameDuration{kCMTimeZero};

    AVURLAsset* asset{nil};
    AVAssetTrack* track{nil};
    AVAssetReader* reader{nil};
    AVAssetReaderTrackOutput* output{nil};
    int64_t currentFrameIndex{-1};

    ~Impl()
    {
        close();
    }

    void close()
    {
        if (reader)
        {
            [reader cancelReading];
            reader = nil;
            output = nil;
        }
        track = nil;
        asset = nil;
        currentFrameIndex = -1;
    }

    bool createReader(int64_t targetFrameIndex)
    {
        if (reader)
        {
            [reader cancelReading];
            reader = nil;
            output = nil;
        }

        NSError* error = nil;
        reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
        if (!reader || error)
        {
            std::cerr << "ERROR: AVFProResRawReader: Failed to create AVAssetReader: "
                      << (error ? [[error localizedDescription] UTF8String] : "unknown error") << std::endl;
            return false;
        }

        CMTime targetTime;
        if (minFrameDuration.timescale > 0 && minFrameDuration.value > 0)
        {
            targetTime = CMTimeMake(targetFrameIndex * minFrameDuration.value, minFrameDuration.timescale);
        }
        else
        {
            targetTime = CMTimeMakeWithSeconds((double)targetFrameIndex / fps, 60000);
        }

        reader.timeRange = CMTimeRangeMake(targetTime, kCMTimePositiveInfinity);

        NSDictionary* outputSettings = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_64RGBAHalf)
        };

        output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outputSettings];
        output.alwaysCopiesSampleData = NO;

        if (![reader canAddOutput:output])
        {
            std::cerr << "ERROR: AVFProResRawReader: cannot add track output to reader" << std::endl;
            reader = nil;
            output = nil;
            return false;
        }

        [reader addOutput:output];

        if (![reader startReading])
        {
            std::cerr << "ERROR: AVFProResRawReader: startReading failed: "
                      << (reader.error ? [[reader.error localizedDescription] UTF8String] : "unknown") << std::endl;
            reader = nil;
            output = nil;
            return false;
        }

        currentFrameIndex = targetFrameIndex - 1;
        return true;
    }
};

AVFProResRawReader::AVFProResRawReader()
    : m_impl(new Impl())
{
}

AVFProResRawReader::~AVFProResRawReader()
{
    delete m_impl;
}

const std::string& AVFProResRawReader::filePath() const
{
    return m_impl->filePath;
}

int AVFProResRawReader::width() const
{
    return m_impl->width;
}

int AVFProResRawReader::height() const
{
    return m_impl->height;
}

int64_t AVFProResRawReader::totalFrames() const
{
    return m_impl->totalFrames;
}

double AVFProResRawReader::fps() const
{
    return m_impl->fps;
}

void AVFProResRawReader::close()
{
    m_impl->close();
}

bool AVFProResRawReader::open(const std::string& filepath, int trackIndex, double fallbackFps)
{
    @autoreleasepool
    {
        m_impl->close();
        m_impl->filePath = filepath;
        m_impl->trackIndex = trackIndex;

        NSString* nsPath = [NSString stringWithUTF8String:filepath.c_str()];
        NSURL* url = [NSURL fileURLWithPath:nsPath];
        m_impl->asset = [AVURLAsset URLAssetWithURL:url options:nil];
        if (!m_impl->asset)
        {
            std::cerr << "ERROR: AVFProResRawReader: Failed to create AVURLAsset for " << filepath << std::endl;
            return false;
        }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray<AVAssetTrack*>* tracks = [m_impl->asset tracksWithMediaType:AVMediaTypeVideo];
#pragma clang diagnostic pop

        if (tracks.count == 0)
        {
            std::cerr << "ERROR: AVFProResRawReader: No video tracks found in " << filepath << std::endl;
            return false;
        }

        if (trackIndex >= 0 && trackIndex < (int)tracks.count)
        {
            m_impl->track = tracks[trackIndex];
        }
        else
        {
            m_impl->track = tracks[0];
        }

        m_impl->width = static_cast<int>(m_impl->track.naturalSize.width);
        m_impl->height = static_cast<int>(m_impl->track.naturalSize.height);

        double trackFps = m_impl->track.nominalFrameRate;
        if (trackFps > 0.0)
        {
            m_impl->fps = trackFps;
        }
        else if (fallbackFps > 0.0)
        {
            m_impl->fps = fallbackFps;
        }
        else
        {
            m_impl->fps = 24.0;
        }

        m_impl->minFrameDuration = m_impl->track.minFrameDuration;

        CMTime duration = m_impl->track.timeRange.duration;
        double durationSec = CMTimeGetSeconds(duration);
        if (durationSec > 0.0)
        {
            m_impl->totalFrames = static_cast<int64_t>(std::round(durationSec * m_impl->fps));
        }

        return true;
    }
}

bool AVFProResRawReader::readFrame(int64_t frameIndex, uint8_t* dst, size_t rowBytes, int outWidth, int outHeight)
{
    @autoreleasepool
    {
        if (!m_impl->track || !m_impl->asset)
        {
            return false;
        }

        // Sequential reading vs seek/jump
        if (!m_impl->reader || frameIndex != m_impl->currentFrameIndex + 1)
        {
            if (!m_impl->createReader(frameIndex))
            {
                return false;
            }
        }

        CMSampleBufferRef sampleBuffer = [m_impl->output copyNextSampleBuffer];
        if (!sampleBuffer)
        {
            // Try recreation once in case of EOF / reader state reset
            if (!m_impl->createReader(frameIndex))
            {
                return false;
            }
            sampleBuffer = [m_impl->output copyNextSampleBuffer];
            if (!sampleBuffer)
            {
                return false;
            }
        }

        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer)
        {
            CFRelease(sampleBuffer);
            return false;
        }

        CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        uint8_t* srcBase = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(imageBuffer));
        size_t srcRowBytes = CVPixelBufferGetBytesPerRow(imageBuffer);
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);

        // 64RGBAHalf: 4 half-floats = 8 bytes per pixel, native RGBA memory layout
        const size_t bytesPerPixel = 8;
        const size_t copyBytesPerRow = std::min(rowBytes, width * bytesPerPixel);
        for (size_t y = 0; y < height; ++y)
        {
            std::memcpy(dst + y * rowBytes, srcBase + y * srcRowBytes, copyBytesPerRow);
        }

        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        CFRelease(sampleBuffer);

        m_impl->currentFrameIndex = frameIndex;
        return true;
    }
}

} // namespace TwkMovie
