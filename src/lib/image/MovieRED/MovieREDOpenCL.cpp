//******************************************************************************
// Copyright (c) 2026 Makai Systems and OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#include <MovieRED/MovieREDOpenCL.h>
#include <CL/opencl.h>
#include <R3DSDK.h>
#include <R3DSDKOpenCL.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstring>
#include <iostream>
#include <mutex>
#include <string>
#include <vector>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace TwkMovie
{
    namespace REDOpenCLGpu
    {
        static std::mutex s_openclMutex;
        static bool s_initialized = false;
        static std::string s_deviceName;

#if defined(_WIN32)
        static HMODULE s_clModule = NULL;
#else
        static void* s_clModule = nullptr;
#endif

        static R3DSDK::EXT_OCLAPI_1_1 s_api;
        static cl_context s_context = nullptr;
        static cl_command_queue s_queue = nullptr;
        static R3DSDK::REDCL* s_redcl = nullptr;
        static R3DSDK::AsyncDecoder* s_asyncDecoder = nullptr;

        // Persistent host and device buffers
        static unsigned char* s_rawHostBufferBase = nullptr;
        static unsigned char* s_rawHostBuffer = nullptr;
        static size_t s_rawHostSize = 0;

        static cl_mem s_rawDeviceBuffer = nullptr;
        static size_t s_rawDeviceBufferSize = 0;

        static cl_mem s_outDeviceBuffer = nullptr;
        static size_t s_outDeviceBufferSize = 0;

        struct FrameCallbackSync
        {
            std::mutex mtx;
            std::condition_variable cv;
            bool done = false;
            R3DSDK::DecodeStatus status = R3DSDK::DSOutputBufferInvalid;
        };

        static void* loadSymbol(const char* name)
        {
            if (!s_clModule)
                return nullptr;
#if defined(_WIN32)
            return reinterpret_cast<void*>(GetProcAddress(s_clModule, name));
#else
            return dlsym(s_clModule, name);
#endif
        }

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

        bool isAvailable() { return s_initialized && (s_redcl != nullptr) && (s_asyncDecoder != nullptr); }

        const char* deviceName() { return s_deviceName.c_str(); }

        bool init(const char* /*libPath*/)
        {
            std::lock_guard<std::mutex> lock(s_openclMutex);
            if (s_initialized)
                return true;

            // 1. Load system OpenCL library dynamically
#if defined(_WIN32)
            s_clModule = LoadLibraryA("OpenCL.dll");
#elif defined(__APPLE__)
            s_clModule = dlopen("/System/Library/Frameworks/OpenCL.framework/OpenCL", RTLD_NOW | RTLD_LOCAL);
#else
            s_clModule = dlopen("libOpenCL.so.1", RTLD_NOW | RTLD_LOCAL);
            if (!s_clModule)
                s_clModule = dlopen("libOpenCL.so", RTLD_NOW | RTLD_LOCAL);
#endif

            if (!s_clModule)
                return false;

            // 2. Resolve required OpenCL API functions into s_api struct
#define RESOLVE_CL(fn)                                                \
    s_api.fn = reinterpret_cast<decltype(s_api.fn)>(loadSymbol(#fn)); \
    if (!s_api.fn)                                                    \
    {                                                                 \
        return false;                                                 \
    }

            RESOLVE_CL(clSetKernelArg);
            RESOLVE_CL(clFlush);
            RESOLVE_CL(clFinish);
            RESOLVE_CL(clEnqueueCopyImage);
            RESOLVE_CL(clCreateContext);
            RESOLVE_CL(clCreateCommandQueue);
            RESOLVE_CL(clCreateSampler);
            RESOLVE_CL(clCreateKernel);
            RESOLVE_CL(clCreateBuffer);
            RESOLVE_CL(clCreateProgramWithSource);
            RESOLVE_CL(clCreateProgramWithBinary);
            RESOLVE_CL(clReleaseEvent);
            RESOLVE_CL(clReleaseSampler);
            RESOLVE_CL(clReleaseKernel);
            RESOLVE_CL(clReleaseMemObject);
            RESOLVE_CL(clReleaseProgram);
            RESOLVE_CL(clReleaseContext);
            RESOLVE_CL(clReleaseCommandQueue);
            RESOLVE_CL(clGetPlatformInfo);
            RESOLVE_CL(clGetDeviceIDs);
            RESOLVE_CL(clGetPlatformIDs);
            RESOLVE_CL(clGetDeviceInfo);
            RESOLVE_CL(clGetContextInfo);
            RESOLVE_CL(clGetImageInfo);
            RESOLVE_CL(clGetProgramBuildInfo);
            RESOLVE_CL(clGetProgramInfo);
            RESOLVE_CL(clGetKernelWorkGroupInfo);
            RESOLVE_CL(clBuildProgram);
            RESOLVE_CL(clEnqueueWriteBuffer);
            RESOLVE_CL(clEnqueueReadBuffer);
            RESOLVE_CL(clEnqueueCopyBuffer);
            RESOLVE_CL(clEnqueueCopyBufferToImage);
            RESOLVE_CL(clEnqueueWriteImage);
            RESOLVE_CL(clEnqueueNDRangeKernel);
            RESOLVE_CL(clEnqueueMapBuffer);
            RESOLVE_CL(clEnqueueUnmapMemObject);
            RESOLVE_CL(clWaitForEvents);
            RESOLVE_CL(clEnqueueBarrier);
            RESOLVE_CL(clEnqueueMarker);
            RESOLVE_CL(clCreateImage2D);
            RESOLVE_CL(clSetMemObjectDestructorCallback);
            RESOLVE_CL(clCreateSubBuffer);
#undef RESOLVE_CL

            // 3. Query GPU device
            cl_uint numPlatforms = 0;
            if (s_api.clGetPlatformIDs(0, nullptr, &numPlatforms) != CL_SUCCESS || numPlatforms == 0)
                return false;

            std::vector<cl_platform_id> platforms(numPlatforms);
            if (s_api.clGetPlatformIDs(numPlatforms, platforms.data(), nullptr) != CL_SUCCESS)
                return false;

            cl_device_id gpuDevice = nullptr;
            for (cl_uint i = 0; i < numPlatforms && !gpuDevice; ++i)
            {
                cl_uint numDevices = 0;
                if (s_api.clGetDeviceIDs(platforms[i], CL_DEVICE_TYPE_GPU, 0, nullptr, &numDevices) == CL_SUCCESS && numDevices > 0)
                {
                    std::vector<cl_device_id> devices(numDevices);
                    if (s_api.clGetDeviceIDs(platforms[i], CL_DEVICE_TYPE_GPU, numDevices, devices.data(), nullptr) == CL_SUCCESS)
                    {
                        gpuDevice = devices[0];
                    }
                }
            }

            if (!gpuDevice)
                return false;

            char devNameBuf[256] = {0};
            s_api.clGetDeviceInfo(gpuDevice, CL_DEVICE_NAME, sizeof(devNameBuf) - 1, devNameBuf, nullptr);
            s_deviceName = devNameBuf;

            cl_int clerr = 0;
            s_context = s_api.clCreateContext(nullptr, 1, &gpuDevice, nullptr, nullptr, &clerr);
            if (clerr != CL_SUCCESS || !s_context)
                return false;

            s_queue = s_api.clCreateCommandQueue(s_context, gpuDevice, 0, &clerr);
            if (clerr != CL_SUCCESS || !s_queue)
            {
                s_api.clReleaseContext(s_context);
                s_context = nullptr;
                return false;
            }

            try
            {
                s_redcl = new R3DSDK::REDCL(s_api, "");
            }
            catch (const std::exception& e)
            {
                std::cerr << "REDOpenCL: Exception creating REDCL: " << e.what() << std::endl;
                s_api.clReleaseCommandQueue(s_queue);
                s_api.clReleaseContext(s_context);
                s_queue = nullptr;
                s_context = nullptr;
                return false;
            }

            R3DSDK::REDCL::Status status = s_redcl->checkCompatibility(s_context, s_queue, clerr);
            if (status != R3DSDK::REDCL::Status_Ok)
            {
                std::cerr << "REDOpenCL: Device compatibility check failed on " << s_deviceName << " (status: " << status
                          << ", clerr: " << clerr << ")" << std::endl;
                delete s_redcl;
                s_redcl = nullptr;
                s_api.clReleaseCommandQueue(s_queue);
                s_api.clReleaseContext(s_context);
                s_queue = nullptr;
                s_context = nullptr;
                return false;
            }

            try
            {
                s_asyncDecoder = new R3DSDK::AsyncDecoder();
            }
            catch (const std::exception& e)
            {
                std::cerr << "REDOpenCL: Failed to initialize AsyncDecoder: " << e.what() << std::endl;
                delete s_redcl;
                s_redcl = nullptr;
                s_api.clReleaseCommandQueue(s_queue);
                s_api.clReleaseContext(s_context);
                s_queue = nullptr;
                s_context = nullptr;
                return false;
            }

            s_initialized = true;
            std::cout << "INFO: Initialized REDOpenCL GPU debayering on " << s_deviceName << std::endl;
            return true;
        }

        void shutdown()
        {
            std::lock_guard<std::mutex> lock(s_openclMutex);
            if (s_asyncDecoder)
            {
                s_asyncDecoder->Close();
                delete s_asyncDecoder;
                s_asyncDecoder = nullptr;
            }

            if (s_redcl)
            {
                delete s_redcl;
                s_redcl = nullptr;
            }

            if (s_rawDeviceBuffer && s_api.clReleaseMemObject)
            {
                s_api.clReleaseMemObject(s_rawDeviceBuffer);
                s_rawDeviceBuffer = nullptr;
                s_rawDeviceBufferSize = 0;
            }

            if (s_outDeviceBuffer && s_api.clReleaseMemObject)
            {
                s_api.clReleaseMemObject(s_outDeviceBuffer);
                s_outDeviceBuffer = nullptr;
                s_outDeviceBufferSize = 0;
            }

            if (s_rawHostBufferBase)
            {
                free(s_rawHostBufferBase);
                s_rawHostBufferBase = nullptr;
                s_rawHostBuffer = nullptr;
                s_rawHostSize = 0;
            }

            if (s_queue && s_api.clReleaseCommandQueue)
            {
                s_api.clReleaseCommandQueue(s_queue);
                s_queue = nullptr;
            }

            if (s_context && s_api.clReleaseContext)
            {
                s_api.clReleaseContext(s_context);
                s_context = nullptr;
            }

#if defined(_WIN32)
            if (s_clModule)
            {
                FreeLibrary(s_clModule);
                s_clModule = NULL;
            }
#else
            if (s_clModule)
            {
                dlclose(s_clModule);
                s_clModule = nullptr;
            }
#endif
            s_initialized = false;
        }

        bool debayerFrame(R3DSDK::Clip* clip, size_t frameNo, uint32_t decodeMode, uint32_t pixelType, unsigned char* outBuffer,
                          size_t outBufferSize, R3DSDK::Metadata* outFrameMetadata)
        {
            if (!isAvailable() || !clip || !outBuffer)
                return false;

            std::lock_guard<std::mutex> lock(s_openclMutex);

            R3DSDK::VideoDecodeMode vmode = static_cast<R3DSDK::VideoDecodeMode>(decodeMode);
            R3DSDK::VideoPixelType vpixel = static_cast<R3DSDK::VideoPixelType>(pixelType);

            R3DSDK::AsyncDecompressJob decompressJob;
            decompressJob.Clip = clip;
            decompressJob.Mode = vmode;
            decompressJob.VideoTrackNo = 0;
            decompressJob.VideoFrameNo = frameNo;
            decompressJob.OutputFrameMetadata = outFrameMetadata;

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

            // Ensure raw OpenCL device buffer
            cl_int clerr = 0;
            if (!s_rawDeviceBuffer || s_rawDeviceBufferSize < rawSize)
            {
                if (s_rawDeviceBuffer)
                    s_api.clReleaseMemObject(s_rawDeviceBuffer);
                s_rawDeviceBuffer = s_api.clCreateBuffer(s_context, CL_MEM_READ_ONLY, rawSize, nullptr, &clerr);
                if (clerr != CL_SUCCESS || !s_rawDeviceBuffer)
                    return false;
                s_rawDeviceBufferSize = rawSize;
            }

            clerr = s_api.clEnqueueWriteBuffer(s_queue, s_rawDeviceBuffer, CL_TRUE, 0, rawSize, s_rawHostBuffer, 0, nullptr, nullptr);
            if (clerr != CL_SUCCESS)
                return false;

            R3DSDK::DebayerOpenCLJob* debayerJob = s_redcl->createDebayerJob();
            if (!debayerJob)
                return false;

            debayerJob->imageProcessingSettings = new R3DSDK::ImageProcessingSettings();
            clip->GetDefaultImageProcessingSettings(*(debayerJob->imageProcessingSettings));
            debayerJob->mode = vmode;
            debayerJob->pixelType = vpixel;
            debayerJob->raw_host_mem = s_rawHostBuffer;
            debayerJob->raw_device_mem = s_rawDeviceBuffer;

            size_t resultSize = R3DSDK::DebayerOpenCLJob::ResultFrameSize(*debayerJob);
            if (resultSize == 0)
            {
                delete debayerJob->imageProcessingSettings;
                s_redcl->releaseDebayerJob(debayerJob);
                return false;
            }

            // Ensure output OpenCL device buffer
            if (!s_outDeviceBuffer || s_outDeviceBufferSize < resultSize)
            {
                if (s_outDeviceBuffer)
                    s_api.clReleaseMemObject(s_outDeviceBuffer);
                s_outDeviceBuffer = s_api.clCreateBuffer(s_context, CL_MEM_WRITE_ONLY, resultSize, nullptr, &clerr);
                if (clerr != CL_SUCCESS || !s_outDeviceBuffer)
                {
                    delete debayerJob->imageProcessingSettings;
                    s_redcl->releaseDebayerJob(debayerJob);
                    return false;
                }
                s_outDeviceBufferSize = resultSize;
            }

            debayerJob->output_device_mem = s_outDeviceBuffer;
            debayerJob->output_device_mem_size = resultSize;

            R3DSDK::REDCL::Status status = s_redcl->process(s_context, s_queue, debayerJob, clerr);
            bool success = (status == R3DSDK::REDCL::Status_Ok);

            if (success)
            {
                size_t copyBytes = std::min(outBufferSize, resultSize);
                clerr = s_api.clEnqueueReadBuffer(s_queue, s_outDeviceBuffer, CL_TRUE, 0, copyBytes, outBuffer, 0, nullptr, nullptr);
                if (clerr != CL_SUCCESS)
                    success = false;
            }

            delete debayerJob->imageProcessingSettings;
            s_redcl->releaseDebayerJob(debayerJob);
            return success;
        }

    } // namespace REDOpenCLGpu
} // namespace TwkMovie
