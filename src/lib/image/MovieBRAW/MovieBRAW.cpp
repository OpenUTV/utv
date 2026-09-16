//******************************************************************************
// Copyright (c) 2026 The OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************
#include <MovieBRAW/MovieBRAW.h>

#include <TwkFB/IO.h>
#include <TwkMath/Function.h>
#include <TwkMovie/Exception.h>
#include <TwkMovie/Movie.h>
#include <TwkMovie/MovieIO.h>
#include <TwkUtil/File.h>

#include "BlackmagicRawAPI.h"
#include "PlatformHelpers.h"
#include "CountingSemaphore.h"

#include <iostream>
#include <sstream>
#include <vector>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <cstring>
#include <algorithm>

namespace TwkMovie
{

    using namespace std;
    using namespace TwkFB;
    using namespace TwkUtil;
    using namespace TwkMovie;

    MovieBRAW::Format MovieBRAW::pixelFormat = MovieBRAW::RGBA8;

    static IBlackmagicRawFactory* getBRAWFactory()
    {
        static std::mutex s_factoryMutex;
        std::lock_guard<std::mutex> lock(s_factoryMutex);

        IBlackmagicRawFactory* factory = CreateBlackmagicRawFactoryInstance();
        if (factory != nullptr)
        {
            return factory;
        }

#if defined(__APPLE__)
        static const char* searchPaths[] = {"/Applications/Blackmagic RAW/Blackmagic RAW Player.app/Contents/Frameworks",
                                            "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Frameworks",
                                            "/Applications/Blackmagic RAW/Blackmagic RAW SDK/Mac/Libraries",
                                            "/Library/Application Support/Blackmagic Design/Blackmagic RAW"};
        for (const char* p : searchPaths)
        {
            CFStringRef cfPath = CFStringCreateWithCString(kCFAllocatorDefault, p, kCFStringEncodingUTF8);
            if (cfPath != nullptr)
            {
                factory = CreateBlackmagicRawFactoryInstanceFromPath(cfPath);
                CFRelease(cfPath);
                if (factory != nullptr)
                {
                    return factory;
                }
            }
        }
#elif defined(_WIN32)
        static const wchar_t* searchPaths[] = {L"C:\\Program Files\\Blackmagic Design\\Blackmagic RAW",
                                               L"C:\\Program Files\\Blackmagic Design\\DaVinci Resolve"};
        for (const wchar_t* p : searchPaths)
        {
            BSTR bstrPath = SysAllocString(p);
            if (bstrPath != nullptr)
            {
                factory = CreateBlackmagicRawFactoryInstanceFromPath(bstrPath);
                SysFreeString(bstrPath);
                if (factory != nullptr)
                {
                    return factory;
                }
            }
        }
#elif defined(__linux__)
        static const char* searchPaths[] = {"/usr/lib", "/usr/local/lib", "/opt/resolve/libs"};
        for (const char* p : searchPaths)
        {
            factory = CreateBlackmagicRawFactoryInstanceFromPath(p);
            if (factory != nullptr)
            {
                return factory;
            }
        }
#endif

        return nullptr;
    }

    struct BrawDecodeContext
    {
        std::mutex mutex;
        std::condition_variable cv;
        bool ready = false;
        HRESULT status = E_FAIL;
        IBlackmagicRawProcessedImage* processedImage = nullptr;
    };

    class BrawFrameCallback : public IBlackmagicRawCallback
    {
    public:
        explicit BrawFrameCallback(BlackmagicRawResourceFormat format)
            : m_resourceFormat(format)
            , m_refCount(1)
        {
        }

        void ReadComplete(IBlackmagicRawJob* readJob, HRESULT result, IBlackmagicRawFrame* frame) override
        {
            BrawDecodeContext* ctx = nullptr;
            if (SUCCEEDED(result) && readJob != nullptr)
            {
                result = readJob->GetUserData(reinterpret_cast<void**>(&ctx));
            }

            if (SUCCEEDED(result) && frame != nullptr)
            {
                result = frame->SetResourceFormat(m_resourceFormat);
            }

            COM::OwningPtr<IBlackmagicRawJob> decodeJob;
            if (SUCCEEDED(result) && frame != nullptr)
            {
                result = frame->CreateJobDecodeAndProcessFrame(nullptr, nullptr, decodeJob.outArg());
            }

            if (SUCCEEDED(result) && decodeJob != nullptr)
            {
                result = decodeJob->SetUserData(ctx);
            }

            if (SUCCEEDED(result) && decodeJob != nullptr)
            {
                result = decodeJob->Submit();
            }

            if (FAILED(result) && ctx != nullptr)
            {
                std::lock_guard<std::mutex> lock(ctx->mutex);
                ctx->status = result;
                ctx->ready = true;
                ctx->cv.notify_one();
            }
        }

        void ProcessComplete(IBlackmagicRawJob* job, HRESULT result, IBlackmagicRawProcessedImage* image) override
        {
            BrawDecodeContext* ctx = nullptr;
            if (job != nullptr)
            {
                job->GetUserData(reinterpret_cast<void**>(&ctx));
            }

            if (ctx != nullptr)
            {
                std::lock_guard<std::mutex> lock(ctx->mutex);
                ctx->status = result;
                if (SUCCEEDED(result) && image != nullptr)
                {
                    image->AddRef();
                    ctx->processedImage = image;
                }
                ctx->ready = true;
                ctx->cv.notify_one();
            }
        }

        void ReadAudioComplete(IBlackmagicRawJob*, HRESULT, IBlackmagicRawAudioBuffer*) override {}

        void DecodeComplete(IBlackmagicRawJob*, HRESULT) override {}

        void TrimProgress(IBlackmagicRawJob*, float) override {}

        void TrimComplete(IBlackmagicRawJob*, HRESULT) override {}

        void SidecarMetadataParseWarning(IBlackmagicRawClip*, COM::NativeString, uint32_t, COM::NativeString) override {}

        void SidecarMetadataParseError(IBlackmagicRawClip*, COM::NativeString, uint32_t, COM::NativeString) override {}

        void PreparePipelineComplete(void*, HRESULT) override {}

        HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID* ppvOut) override
        {
            if (ppvOut == nullptr)
                return E_POINTER;

            const REFIID unknownId = IID_IUnknown;
            if (std::memcmp(&iid, &unknownId, sizeof(REFIID)) == 0)
            {
                *ppvOut = static_cast<IUnknown*>(this);
                AddRef();
                return S_OK;
            }
            else if (std::memcmp(&iid, &IID_IBlackmagicRawCallback, sizeof(REFIID)) == 0)
            {
                *ppvOut = static_cast<IBlackmagicRawCallback*>(this);
                AddRef();
                return S_OK;
            }

            *ppvOut = nullptr;
            return E_NOINTERFACE;
        }

        ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refCount; }

        ULONG STDMETHODCALLTYPE Release() override
        {
            const ULONG newCount = --m_refCount;
            if (newCount == 0)
                delete this;
            return newCount;
        }

    private:
        BlackmagicRawResourceFormat m_resourceFormat;
        std::atomic<ULONG> m_refCount;
    };

    struct MovieBRAW::Impl
    {
        COM::Initialiser comInit;
        COM::OwningPtr<IBlackmagicRaw> codec;
        COM::OwningPtr<IBlackmagicRawClip> clip;
        BrawFrameCallback* callback = nullptr;
        std::mutex clipMutex;
        uint32_t width = 0;
        uint32_t height = 0;
        float fps = 24.0f;
        uint64_t frameCount = 0;
        std::string cameraType;

        ~Impl()
        {
            if (codec)
            {
                codec->SetCallback(nullptr);
                codec->FlushJobs();
            }
            if (callback)
            {
                callback->Release();
                callback = nullptr;
            }
        }
    };

    MovieBRAW::MovieBRAW()
        : MovieReader()
        , m_impl(nullptr)
    {
        m_threadSafe = true;
    }

    MovieBRAW::~MovieBRAW()
    {
        delete m_impl;
        m_impl = nullptr;
    }

    MovieReader* MovieBRAW::clone() const
    {
        MovieBRAW* mov = new MovieBRAW();
        if (!m_filename.empty())
        {
            mov->preloadOpen(m_filename, m_request);
        }
        return mov;
    }

    void MovieBRAW::postPreloadOpen(const MovieInfo& /*unused*/, const Movie::ReadRequest& /*unused*/) {}

    void MovieBRAW::preloadOpen(const string& filename, const ReadRequest& request)
    {
        m_filename = filename;
        m_request = request;

        IBlackmagicRawFactory* factory = getBRAWFactory();
        if (factory == nullptr)
        {
            TWK_THROW_STREAM(IOException, "Blackmagic RAW runtime not found. Please install the free Blackmagic RAW Player "
                                          "(blackmagicdesign.com/support) to enable .braw playback: "
                                              << filename);
        }

        delete m_impl;
        m_impl = new Impl();

        HRESULT hr = factory->CreateCodec(m_impl->codec.outArg());
        if (FAILED(hr) || !m_impl->codec)
        {
            TWK_THROW_STREAM(IOException, "Failed to initialize Blackmagic RAW codec engine: " << filename);
        }

        COM::String clipName(filename.c_str());
        hr = m_impl->codec->OpenClip(clipName, m_impl->clip.outArg());
        if (FAILED(hr) || !m_impl->clip)
        {
            TWK_THROW_STREAM(IOException, "Failed to open Blackmagic RAW clip: " << filename);
        }

        m_impl->clip->GetWidth(&m_impl->width);
        m_impl->clip->GetHeight(&m_impl->height);
        m_impl->clip->GetFrameRate(&m_impl->fps);
        m_impl->clip->GetFrameCount(&m_impl->frameCount);

        COM::String camType;
        if (SUCCEEDED(m_impl->clip->GetCameraType(camType.outArg())))
        {
            m_impl->cameraType = camType.str();
        }

        BlackmagicRawResourceFormat resFormat = blackmagicRawResourceFormatRGBAU8;
        if (pixelFormat == RGBA16)
            resFormat = blackmagicRawResourceFormatRGBAU16;
        else if (pixelFormat == RGBA_FLOAT)
            resFormat = blackmagicRawResourceFormatRGBAF32;

        m_impl->callback = new BrawFrameCallback(resFormat);
        m_impl->codec->SetCallback(m_impl->callback);

        m_info.start = 1;
        m_info.end = (m_impl->frameCount > 0) ? static_cast<int>(m_impl->frameCount) : 1;
        m_info.inc = 1;
        m_info.fps = (m_impl->fps > 0.0f) ? m_impl->fps : 24.0f;
        m_info.width = m_impl->width;
        m_info.height = m_impl->height;
        m_info.uncropWidth = m_impl->width;
        m_info.uncropHeight = m_impl->height;
        m_info.uncropX = 0;
        m_info.uncropY = 0;
        m_info.pixelAspect = 1.0f;
        m_info.video = true;
        m_info.audio = false;
        m_info.orientation = FrameBuffer::TOPLEFT;
        m_info.numChannels = 4;
        if (pixelFormat == RGBA16)
            m_info.dataType = FrameBuffer::USHORT;
        else if (pixelFormat == RGBA_FLOAT)
            m_info.dataType = FrameBuffer::FLOAT;
        else
            m_info.dataType = FrameBuffer::UCHAR;
    }

    void MovieBRAW::imagesAtFrame(const ReadRequest& request, FrameBufferVector& fbs)
    {
        if (!m_impl || !m_impl->clip)
        {
            TWK_THROW_STREAM(IOException, "BRAW clip not open: " << m_filename);
        }

        int frame = request.frame;
        uint64_t frameIndex = 0;
        if (frame >= m_info.start && frame <= m_info.end)
        {
            frameIndex = static_cast<uint64_t>(frame - m_info.start);
        }
        else if (m_impl->frameCount > 0)
        {
            int clamped = std::clamp(frame - m_info.start, 0, static_cast<int>(m_impl->frameCount - 1));
            frameIndex = static_cast<uint64_t>(clamped);
        }

        fbs.resize(1);
        if (!fbs.front())
            fbs.front() = new FrameBuffer();

        FrameBuffer& fb = *fbs.front();

        FrameBuffer::DataType dt = FrameBuffer::UCHAR;
        if (pixelFormat == RGBA16)
            dt = FrameBuffer::USHORT;
        else if (pixelFormat == RGBA_FLOAT)
            dt = FrameBuffer::FLOAT;

        fb.restructure(m_impl->width, m_impl->height, 0, 4, dt, nullptr, nullptr, FrameBuffer::TOPLEFT);

        BrawDecodeContext ctx;
        {
            std::lock_guard<std::mutex> lock(m_impl->clipMutex);
            COM::OwningPtr<IBlackmagicRawJob> jobRead;
            HRESULT hr = m_impl->clip->CreateJobReadFrame(frameIndex, jobRead.outArg());
            if (SUCCEEDED(hr) && jobRead)
            {
                jobRead->SetUserData(&ctx);
                hr = jobRead->Submit();
            }
            if (FAILED(hr))
            {
                TWK_THROW_STREAM(IOException, "Failed to submit read job for frame " << frameIndex << " in: " << m_filename);
            }
        }

        {
            std::unique_lock<std::mutex> lock(ctx.mutex);
            ctx.cv.wait(lock, [&ctx]() { return ctx.ready; });
        }

        if (FAILED(ctx.status) || ctx.processedImage == nullptr)
        {
            TWK_THROW_STREAM(IOException, "Failed to decode BRAW frame " << frameIndex << " in: " << m_filename);
        }

        void* pixelData = nullptr;
        uint32_t sizeBytes = 0;
        ctx.processedImage->GetResource(&pixelData);
        ctx.processedImage->GetResourceSizeBytes(&sizeBytes);

        if (pixelData != nullptr && sizeBytes > 0)
        {
            size_t copySize = std::min(static_cast<size_t>(sizeBytes), fb.allocSize());
            std::memcpy(fb.scanline<unsigned char>(0), pixelData, copySize);
        }

        ctx.processedImage->Release();
        ctx.processedImage = nullptr;

        fb.setIdentifier("");
        identifier(frame, fb.idstream());
        fb.addAttribute(new StringAttribute("File", m_filename));
        fb.addAttribute(new StringAttribute("BRAW/CameraType", m_impl->cameraType));
        fb.addAttribute(new IntAttribute("BRAW/FrameIndex", static_cast<int>(frameIndex)));
        fb.addAttribute(new IntAttribute("BRAW/TotalFrames", static_cast<int>(m_impl->frameCount)));
    }

    void MovieBRAW::identifiersAtFrame(const ReadRequest& request, IdentifierVector& ids)
    {
        int frame = request.frame;
        ostringstream str;
        identifier(frame, str);
        ids.resize(1);
        ids.front() = str.str();
    }

    void MovieBRAW::identifier(int frame, ostream& o)
    {
        if (frame < m_info.start)
            frame = m_info.start;
        if (frame > m_info.end)
            frame = m_info.end;
        o << frame << ":" << m_filename;
    }

    //----------------------------------------------------------------------

    MovieBRAWIO::MovieBRAWIO()
        : MovieIO("MovieBRAW", "v1")
    {
        StringPairVector video;
        StringPairVector audio;
        unsigned int capabilities = MovieIO::MovieRead | MovieIO::AttributeRead;
        addType("braw", "Blackmagic RAW Movie", capabilities, video, audio);
        addType("BRAW", "Blackmagic RAW Movie", capabilities, video, audio);
    }

    MovieBRAWIO::~MovieBRAWIO() {}

    std::string MovieBRAWIO::about() const { return "Blackmagic RAW (BRAW) Movie Reader"; }

    MovieReader* MovieBRAWIO::movieReader() const { return new MovieBRAW(); }

    MovieWriter* MovieBRAWIO::movieWriter() const { return nullptr; }

    void MovieBRAWIO::getMovieInfo(const std::string& filename, MovieInfo& info) const
    {
        MovieBRAW reader;
        Movie::ReadRequest request;
        reader.preloadOpen(filename, request);
        info = reader.info();
    }

} // namespace TwkMovie
