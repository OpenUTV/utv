//******************************************************************************
// Copyright (c) 2026 Makai Systems and OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#if defined(__APPLE__)

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

#include <MovieRED/MovieREDMetal.h>
#include <R3DSDK.h>
#include <R3DSDKMetal.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <iostream>
#include <memory>
#include <mutex>
#include <vector>

namespace TwkMovie
{
    namespace REDMetalGpu
    {
        static std::mutex s_metalMutex;
        static bool s_initialized = false;
        static id<MTLDevice> s_device = nil;
        static id<MTLCommandQueue> s_queue = nil;
        static R3DSDK::REDMetal* s_redMetal = nullptr;
        static R3DSDK::AsyncDecoder* s_asyncDecoder = nullptr;

        // Cached persistent buffers to eliminate per-frame GPU allocation overhead
        static unsigned char* s_rawHostBufferBase = nullptr;
        static unsigned char* s_rawHostBuffer = nullptr;
        static size_t s_rawHostSize = 0;

        static id<MTLBuffer> s_rawDeviceBuffer = nil;
        static id<MTLBuffer> s_outDeviceBuffer = nil;

        struct FrameCallbackSync
        {
            std::mutex mtx;
            std::condition_variable cv;
            bool done = false;
            R3DSDK::DecodeStatus status = R3DSDK::DSOutputBufferInvalid;
        };

        static void ensureHostBuffer(size_t sizeNeeded)
        {
            if (s_rawHostSize >= sizeNeeded && s_rawHostBuffer)
                return;

            if (s_rawHostBufferBase)
            {
                free(s_rawHostBufferBase);
                s_rawHostBufferBase = nullptr;
                s_rawHostBuffer = nullptr;
                s_rawHostSize = 0;
            }

            size_t allocSize = sizeNeeded + 32;
            s_rawHostBufferBase = static_cast<unsigned char*>(malloc(allocSize));
            if (!s_rawHostBufferBase)
                return;

            uintptr_t ptr = reinterpret_cast<uintptr_t>(s_rawHostBufferBase);
            size_t offset = (16U - (ptr % 16U)) % 16U;
            s_rawHostBuffer = s_rawHostBufferBase + offset;
            s_rawHostSize = sizeNeeded;
        }

        bool isAvailable()
        {
            return s_initialized && (s_redMetal != nullptr) && (s_asyncDecoder != nullptr);
        }

        bool init(const char* /*libPath*/)
        {
            std::lock_guard<std::mutex> lock(s_metalMutex);
            if (s_initialized)
                return true;

            @autoreleasepool
            {
                s_device = MTLCreateSystemDefaultDevice();
                if (!s_device)
                {
                    std::cerr << "REDMetal: No default Metal device found." << std::endl;
                    return false;
                }

                s_queue = [s_device newCommandQueue];
                if (!s_queue)
                {
                    std::cerr << "REDMetal: Failed to create MTLCommandQueue." << std::endl;
                    return false;
                }

                R3DSDK::EXT_METAL_API api;
                try
                {
                    s_redMetal = new R3DSDK::REDMetal(api);
                }
                catch (const std::exception& e)
                {
                    std::cerr << "REDMetal: Exception creating REDMetal: " << e.what() << std::endl;
                    return false;
                }
                catch (...)
                {
                    std::cerr << "REDMetal: Unknown exception creating REDMetal." << std::endl;
                    return false;
                }

                int err = 0;
                R3DSDK::REDMetal::Status status = s_redMetal->checkCompatibility(s_queue, err);
                if (status != R3DSDK::REDMetal::Status_Ok)
                {
                    std::cerr << "REDMetal: Metal device compatibility check failed (status: " << status << ", err: " << err << ")" << std::endl;
                    delete s_redMetal;
                    s_redMetal = nullptr;
                    return false;
                }

                try
                {
                    s_asyncDecoder = new R3DSDK::AsyncDecoder();
                    size_t threads = s_asyncDecoder->ThreadsAvailable();
                    s_asyncDecoder->Open(threads);
                }
                catch (const std::exception& e)
                {
                    std::cerr << "REDMetal: Failed to initialize AsyncDecoder: " << e.what() << std::endl;
                    delete s_redMetal;
                    s_redMetal = nullptr;
                    delete s_asyncDecoder;
                    s_asyncDecoder = nullptr;
                    return false;
                }

                s_initialized = true;
                std::cout << "INFO: Initialized REDMetal GPU debayering on "
                          << [[s_device name] UTF8String] << std::endl;
                return true;
            }
        }

        void shutdown()
        {
            std::lock_guard<std::mutex> lock(s_metalMutex);
            if (s_asyncDecoder)
            {
                s_asyncDecoder->Close();
                delete s_asyncDecoder;
                s_asyncDecoder = nullptr;
            }

            if (s_redMetal)
            {
                delete s_redMetal;
                s_redMetal = nullptr;
            }

            if (s_rawHostBufferBase)
            {
                free(s_rawHostBufferBase);
                s_rawHostBufferBase = nullptr;
                s_rawHostBuffer = nullptr;
                s_rawHostSize = 0;
            }

            s_rawDeviceBuffer = nil;
            s_outDeviceBuffer = nil;
            s_queue = nil;
            s_device = nil;
            s_initialized = false;
        }

        bool debayerFrame(
            R3DSDK::Clip* clip,
            size_t frameNo,
            uint32_t decodeMode,
            uint32_t pixelType,
            unsigned char* outBuffer,
            size_t outBufferSize
        )
        {
            if (!isAvailable() || !clip || !outBuffer)
                return false;

            std::lock_guard<std::mutex> lock(s_metalMutex);

            @autoreleasepool
            {
                R3DSDK::VideoDecodeMode vmode = static_cast<R3DSDK::VideoDecodeMode>(decodeMode);
                R3DSDK::VideoPixelType vpixel = static_cast<R3DSDK::VideoPixelType>(pixelType);

                R3DSDK::AsyncDecompressJob decompressJob;
                decompressJob.Clip = clip;
                decompressJob.Mode = vmode;
                decompressJob.VideoTrackNo = 0;
                decompressJob.VideoFrameNo = frameNo;

                size_t rawSize = R3DSDK::AsyncDecoder::GetSizeBufferNeeded(decompressJob);
                if (rawSize == 0)
                    return false;

                ensureHostBuffer(rawSize);
                if (!s_rawHostBuffer)
                    return false;

                decompressJob.OutputBuffer = s_rawHostBuffer;
                decompressJob.OutputBufferSize = rawSize;

                FrameCallbackSync syncCtx;
                decompressJob.PrivateData = &syncCtx;
                decompressJob.Callback = [](R3DSDK::AsyncDecompressJob* item, R3DSDK::DecodeStatus status)
                {
                    if (item && item->PrivateData)
                    {
                        auto* ctx = static_cast<FrameCallbackSync*>(item->PrivateData);
                        std::lock_guard<std::mutex> lk(ctx->mtx);
                        ctx->status = status;
                        ctx->done = true;
                        ctx->cv.notify_one();
                    }
                };

                R3DSDK::DecodeStatus dstatus = s_asyncDecoder->DecodeForGpuSdk(decompressJob);
                if (dstatus != R3DSDK::DSDecodeOK)
                    return false;

                {
                    std::unique_lock<std::mutex> lk(syncCtx.mtx);
                    syncCtx.cv.wait(lk, [&] { return syncCtx.done; });
                }

                if (syncCtx.status != R3DSDK::DSDecodeOK)
                    return false;

                // Ensure raw device buffer
                if (!s_rawDeviceBuffer || [s_rawDeviceBuffer length] < rawSize)
                {
                    s_rawDeviceBuffer = [s_device newBufferWithLength:rawSize options:MTLResourceStorageModeManaged];
                    if (!s_rawDeviceBuffer)
                        return false;
                }

                memcpy([s_rawDeviceBuffer contents], s_rawHostBuffer, rawSize);
                [s_rawDeviceBuffer didModifyRange:NSMakeRange(0, rawSize)];

                R3DSDK::DebayerMetalJob* debayerJob = s_redMetal->createDebayerJob();
                if (!debayerJob)
                    return false;

                debayerJob->imageProcessingSettings = new R3DSDK::ImageProcessingSettings();
                clip->GetDefaultImageProcessingSettings(*(debayerJob->imageProcessingSettings));
                debayerJob->mode = vmode;
                debayerJob->pixelType = vpixel;
                debayerJob->raw_host_mem = s_rawHostBuffer;
                debayerJob->raw_device_mem = s_rawDeviceBuffer;

                size_t resultSize = R3DSDK::DebayerMetalJob::ResultFrameSize(*debayerJob);
                if (resultSize == 0)
                {
                    delete debayerJob->imageProcessingSettings;
                    s_redMetal->releaseDebayerJob(debayerJob);
                    return false;
                }

                // Ensure output device buffer
                if (!s_outDeviceBuffer || [s_outDeviceBuffer length] < resultSize)
                {
                    s_outDeviceBuffer = [s_device newBufferWithLength:resultSize options:MTLResourceStorageModeManaged];
                    if (!s_outDeviceBuffer)
                    {
                        delete debayerJob->imageProcessingSettings;
                        s_redMetal->releaseDebayerJob(debayerJob);
                        return false;
                    }
                }

                debayerJob->output_device_mem = s_outDeviceBuffer;
                debayerJob->output_device_mem_size = resultSize;

                int err = 0;
                R3DSDK::REDMetal::Status mstatus = s_redMetal->process(s_queue, debayerJob, err);

                bool success = (mstatus == R3DSDK::REDMetal::Status_Ok);
                if (success)
                {
                    id<MTLCommandBuffer> cb = [s_queue commandBuffer];
                    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
                    [blit synchronizeResource:s_outDeviceBuffer];
                    [blit endEncoding];
                    [cb commit];
                    [cb waitUntilCompleted];

                    size_t copyBytes = std::min(outBufferSize, resultSize);
                    memcpy(outBuffer, [s_outDeviceBuffer contents], copyBytes);
                }

                delete debayerJob->imageProcessingSettings;
                s_redMetal->releaseDebayerJob(debayerJob);
                return success;
            }
        }

    } // namespace REDMetalGpu
} // namespace TwkMovie

#endif // __APPLE__
