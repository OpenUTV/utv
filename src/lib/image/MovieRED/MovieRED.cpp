//******************************************************************************
// Copyright (c) 2026 The OpenUTV Contributors. All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
//******************************************************************************

#include <MovieRED/MovieRED.h>
#include <TwkFB/Exception.h>
#include <TwkFB/Operations.h>
#include <TwkUtil/File.h>
#include <TwkUtil/PathConform.h>

#include <QtCore/QSettings>
#include <QtCore/QString>

#if defined(__APPLE__)
#include <MovieRED/MovieREDMetal.h>
#endif

#include <R3DSDK.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <mutex>
#include <sstream>
#include <sys/stat.h>
#include <vector>

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#elif defined(_WIN32)
#include <windows.h>
#elif defined(__linux__)
#include <unistd.h>
#endif

namespace TwkMovie
{

    using namespace std;
    using namespace TwkFB;
    using namespace TwkUtil;
    using namespace TwkMovie;

    MovieRED::Format MovieRED::pixelFormat = MovieRED::RGB16;
    MovieRED::Resolution MovieRED::resolution = MovieRED::FULL_RES;

    static bool s_redInitialized = false;
    static std::mutex s_redInitMutex;

    static bool fileExists(const std::string& path)
    {
        struct stat st;
        return ::stat(path.c_str(), &st) == 0;
    }

    static bool ensureREDInitialized()
    {
        std::lock_guard<std::mutex> lock(s_redInitMutex);
        if (s_redInitialized)
            return true;

        std::vector<std::string> searchDirs;

        if (const char* envPath = getenv("RED_SDK_PATH"))
            searchDirs.push_back(envPath);
        if (const char* envPath = getenv("R3DSDK_DIR"))
            searchDirs.push_back(envPath);

#if defined(__APPLE__)
        char execPath[1024];
        uint32_t size = sizeof(execPath);
        if (_NSGetExecutablePath(execPath, &size) == 0)
        {
            std::string ep(execPath);
            size_t lastSlash = ep.rfind('/');
            if (lastSlash != std::string::npos)
            {
                std::string macosDir = ep.substr(0, lastSlash);
                searchDirs.push_back(macosDir);
                searchDirs.push_back(macosDir + "/../PlugIns/MovieFormats");
                searchDirs.push_back(macosDir + "/../Frameworks");
                searchDirs.push_back(macosDir + "/../lib");
            }
        }
        searchDirs.push_back("/Users/moliver/dev/openutv/proprietarySDKs/R3DSDKv9_2_1/Redistributable/mac");
        searchDirs.push_back("/Applications/REDCINE-X PRO/REDCINE-X PRO.app/Contents/MacOS");
        searchDirs.push_back("/Applications/REDCINE-X PRO/REDCINE-X PRO.app/Contents/Frameworks");
        searchDirs.push_back("/Library/Application Support/RED");
        searchDirs.push_back("/usr/local/lib");
        searchDirs.push_back("/opt/homebrew/lib");
#elif defined(_WIN32)
        wchar_t exePath[MAX_PATH];
        if (GetModuleFileNameW(NULL, exePath, MAX_PATH))
        {
            std::wstring wep(exePath);
            size_t lastSlash = wep.rfind(L'\\');
            if (lastSlash != std::wstring::npos)
            {
                std::string binDir(wep.begin(), wep.begin() + lastSlash);
                searchDirs.push_back(binDir);
                searchDirs.push_back(binDir + "\\PlugIns\\MovieFormats");
            }
        }
        searchDirs.push_back("C:/Program Files/RED/REDCINE-X PRO");
        searchDirs.push_back("C:/Program Files/RED Digital Cinema");
#elif defined(__linux__)
        searchDirs.push_back("/usr/local/lib");
        searchDirs.push_back("/opt/red");
#endif
        searchDirs.push_back(".");

        const char* targetLib =
#if defined(__APPLE__)
            "REDR3D.dylib";
#elif defined(_WIN32)
            "REDR3D-x64.dll";
#else
            "libREDR3D.so";
#endif

        for (const auto& dir : searchDirs)
        {
            std::string fullPath = dir + "/" + targetLib;
            if (fileExists(fullPath))
            {
#if defined(__APPLE__)
                unsigned int options = OPTION_RED_METAL;
#else
                unsigned int options = OPTION_RED_NONE;
#endif
                R3DSDK::InitializeStatus st = R3DSDK::InitializeSdk(dir.c_str(), options);
                if (st != R3DSDK::ISInitializeOK && options != OPTION_RED_NONE)
                {
                    st = R3DSDK::InitializeSdk(dir.c_str(), OPTION_RED_NONE);
                    options = OPTION_RED_NONE;
                }

                if (st == R3DSDK::ISInitializeOK)
                {
                    s_redInitialized = true;
                    std::cout << "INFO: Initialized RED SDK from " << dir << ": " << R3DSDK::GetSdkVersion() << std::endl;
#if defined(__APPLE__)
                    if (options & OPTION_RED_METAL)
                    {
                        REDMetalGpu::init(dir.c_str());
                    }
#endif
                    return true;
                }
            }
        }

        return false;
    }

    static unsigned char* AlignedMalloc(size_t& sizeNeeded)
    {
        unsigned char* buffer = static_cast<unsigned char*>(malloc(sizeNeeded + 15U));
        if (!buffer)
            return nullptr;
        sizeNeeded = 0U;
        uintptr_t ptr = reinterpret_cast<uintptr_t>(buffer);
        if ((ptr % 16U) == 0U)
            return buffer;
        sizeNeeded = 16U - (ptr % 16U);
        return buffer + sizeNeeded;
    }

    struct MovieRED::Impl
    {
        std::unique_ptr<R3DSDK::Clip> clip;
        std::mutex clipMutex;
        Resolution clipResolution = HALF_RES;
        bool useGpu = true;
        uint32_t fullWidth = 0;
        uint32_t fullHeight = 0;
        uint32_t decodeWidth = 0;
        uint32_t decodeHeight = 0;
        float fps = 24.0f;
        uint64_t frameCount = 0;
        std::string cameraModel;
        std::string cameraPin;
        std::string colorScience;

        ~Impl() { clip.reset(); }
    };

    MovieRED::MovieRED()
        : MovieReader()
        , m_impl(nullptr)
    {
        m_threadSafe = true;
    }

    MovieRED::~MovieRED()
    {
        delete m_impl;
        m_impl = nullptr;
    }

    MovieReader* MovieRED::clone() const
    {
        MovieRED* mov = new MovieRED();
        if (!m_filename.empty())
        {
            mov->preloadOpen(m_filename, m_request);
        }
        return mov;
    }

    void MovieRED::postPreloadOpen(const MovieInfo& /*unused*/, const Movie::ReadRequest& /*unused*/) {}

    void MovieRED::preloadOpen(const std::string& filename, const ReadRequest& request)
    {
        if (!ensureREDInitialized())
        {
            TWK_THROW_STREAM(IOException, "Cannot open RED file: RED dynamic libraries (REDR3D) not found. "
                                          "Please install RED SDK or set RED_SDK_PATH to the redistributable folder.");
        }

        m_filename = filename;
        m_request = request;

        delete m_impl;
        m_impl = new Impl();

        m_impl->clip = std::make_unique<R3DSDK::Clip>(filename.c_str());
        R3DSDK::LoadStatus status = m_impl->clip->Status();
        if (status != R3DSDK::LSClipLoaded)
        {
            TWK_THROW_STREAM(IOException, "Failed to load RED clip: " << filename << " (load status: " << status << ")");
        }

        m_impl->fullWidth = static_cast<uint32_t>(m_impl->clip->Width());
        m_impl->fullHeight = static_cast<uint32_t>(m_impl->clip->Height());
        m_impl->frameCount = static_cast<uint64_t>(m_impl->clip->VideoFrameCount());
        m_impl->fps = m_impl->clip->VideoAudioFramerate();

        if (m_impl->fps <= 0.0f)
            m_impl->fps = 24.0f;

        if (m_impl->frameCount == 0)
            m_impl->frameCount = 1;

        // Query user settings
        QSettings settings;
        settings.beginGroup("R3D");
        QString resSetting = settings.value("resolution", "half").toString();
        bool gpuSetting = settings.value("gpu_acceleration", true).toBool();
        settings.endGroup();

        if (resSetting == "full")
            m_impl->clipResolution = FULL_RES;
        else if (resSetting == "quarter")
            m_impl->clipResolution = QUARTER_RES;
        else if (resSetting == "eighth")
            m_impl->clipResolution = EIGHTH_RES;
        else
            m_impl->clipResolution = HALF_RES;

        m_impl->useGpu = gpuSetting;

        // Environment variable override if specified
        if (const char* args = getenv("MOVIERED_ARGS"))
        {
            std::string s(args);
            if (s.find("resolution=full") != std::string::npos)
                m_impl->clipResolution = FULL_RES;
            else if (s.find("resolution=half") != std::string::npos)
                m_impl->clipResolution = HALF_RES;
            else if (s.find("resolution=quarter") != std::string::npos)
                m_impl->clipResolution = QUARTER_RES;
            else if (s.find("resolution=eighth") != std::string::npos)
                m_impl->clipResolution = EIGHTH_RES;
        }

        if (m_impl->clipResolution == HALF_RES)
        {
            m_impl->decodeWidth = m_impl->fullWidth / 2;
            m_impl->decodeHeight = m_impl->fullHeight / 2;
        }
        else if (m_impl->clipResolution == QUARTER_RES)
        {
            m_impl->decodeWidth = m_impl->fullWidth / 4;
            m_impl->decodeHeight = m_impl->fullHeight / 4;
        }
        else if (m_impl->clipResolution == EIGHTH_RES)
        {
            m_impl->decodeWidth = m_impl->fullWidth / 8;
            m_impl->decodeHeight = m_impl->fullHeight / 8;
        }
        else
        {
            m_impl->decodeWidth = m_impl->fullWidth;
            m_impl->decodeHeight = m_impl->fullHeight;
        }

        R3DSDK::ColorVersion cv = m_impl->clip->DefaultColorVersion();
        if (cv == R3DSDK::ColorVersion3)
            m_impl->colorScience = "IPP2";
        else if (cv == R3DSDK::ColorVersionBC)
            m_impl->colorScience = "Broadcast";
        else
            m_impl->colorScience = "Legacy";

        m_info.width = m_impl->decodeWidth;
        m_info.height = m_impl->decodeHeight;
        m_info.uncropWidth = m_impl->fullWidth;
        m_info.uncropHeight = m_impl->fullHeight;
        m_info.uncropX = 0;
        m_info.uncropY = 0;
        m_info.pixelAspect = 1.0f;
        m_info.start = 1;
        m_info.end = static_cast<int>(m_impl->frameCount);
        m_info.fps = m_impl->fps;
        m_info.video = true;
        m_info.audio = false;
        m_info.slowRandomAccess = true;

        if (pixelFormat == RGBA16 || pixelFormat == RGBA8)
            m_info.numChannels = 4;
        else
            m_info.numChannels = 3;

        if (pixelFormat == RGB_HALF)
            m_info.dataType = FrameBuffer::HALF;
        else if (pixelFormat == RGBA8)
            m_info.dataType = FrameBuffer::UCHAR;
        else
            m_info.dataType = FrameBuffer::USHORT;
    }

    void MovieRED::imagesAtFrame(const ReadRequest& request, FrameBufferVector& fbs)
    {
        if (!m_impl || !m_impl->clip)
        {
            TWK_THROW_STREAM(IOException, "RED clip not open: " << m_filename);
        }

        int frame = request.frame;
        size_t videoFrameNo = 0;
        if (frame >= m_info.start && frame <= m_info.end)
        {
            videoFrameNo = static_cast<size_t>(frame - m_info.start);
        }
        else if (m_impl->frameCount > 0)
        {
            int clamped = std::clamp(frame - m_info.start, 0, static_cast<int>(m_impl->frameCount - 1));
            videoFrameNo = static_cast<size_t>(clamped);
        }

        fbs.resize(1);
        if (!fbs.front())
            fbs.front() = new FrameBuffer();

        FrameBuffer& fb = *fbs.front();

        uint32_t w = m_impl->decodeWidth;
        uint32_t h = m_impl->decodeHeight;
        int numChannels = m_info.numChannels;
        FrameBuffer::DataType dt = m_info.dataType;

        fb.restructure(w, h, 0, numChannels, dt, nullptr, nullptr, FrameBuffer::TOPLEFT);

        R3DSDK::VideoDecodeMode jobMode;
        if (m_impl->clipResolution == HALF_RES)
            jobMode = R3DSDK::DECODE_HALF_RES_GOOD;
        else if (m_impl->clipResolution == QUARTER_RES)
            jobMode = R3DSDK::DECODE_QUARTER_RES_GOOD;
        else if (m_impl->clipResolution == EIGHTH_RES)
            jobMode = R3DSDK::DECODE_EIGHT_RES_GOOD;
        else
            jobMode = R3DSDK::DECODE_FULL_RES_PREMIUM;

        R3DSDK::VideoPixelType jobPixelType;
        if (pixelFormat == RGB_HALF)
            jobPixelType = R3DSDK::PixelType_HalfFloat_RGB_Interleaved;
        else
            jobPixelType = R3DSDK::PixelType_16Bit_RGB_Interleaved;

        size_t bytesPerPixel = (pixelFormat == RGBA8) ? (4 * sizeof(uint8_t)) : (3 * sizeof(uint16_t));
        size_t memNeeded = static_cast<size_t>(w) * static_cast<size_t>(h) * bytesPerPixel;
        size_t adjusted = memNeeded;
        unsigned char* imgBuffer = AlignedMalloc(adjusted);
        if (!imgBuffer)
        {
            TWK_THROW_STREAM(IOException, "Failed to allocate memory for RED decode: " << memNeeded << " bytes");
        }

        bool decodedOnGpu = false;
#if defined(__APPLE__)
        if (m_impl->useGpu && REDMetalGpu::isAvailable() && pixelFormat != RGBA8)
        {
            decodedOnGpu = REDMetalGpu::debayerFrame(m_impl->clip.get(), videoFrameNo, jobMode, jobPixelType, imgBuffer, memNeeded);
        }
#endif

        if (!decodedOnGpu)
        {
            R3DSDK::VideoDecodeJob job;
            job.Mode = jobMode;
            job.PixelType = (pixelFormat == RGBA8) ? R3DSDK::PixelType_8Bit_BGRA_Interleaved : jobPixelType;
            job.OutputBuffer = imgBuffer;
            job.OutputBufferSize = memNeeded;

            R3DSDK::DecodeStatus dstatus;
            {
                std::lock_guard<std::mutex> lock(m_impl->clipMutex);
                dstatus = m_impl->clip->DecodeVideoFrame(videoFrameNo, job);
            }

            if (dstatus != R3DSDK::DSDecodeOK)
            {
                free(imgBuffer - adjusted);
                TWK_THROW_STREAM(IOException, "RED decode failed for frame " << videoFrameNo << " (status: " << dstatus << ")");
            }
        }

        if (pixelFormat == RGBA16)
        {
            const uint16_t* src = reinterpret_cast<const uint16_t*>(imgBuffer);
            uint16_t* dst = fb.scanline<uint16_t>(0);
            size_t numPixels = static_cast<size_t>(w) * static_cast<size_t>(h);
            for (size_t i = 0; i < numPixels; ++i)
            {
                dst[i * 4 + 0] = src[i * 3 + 0];
                dst[i * 4 + 1] = src[i * 3 + 1];
                dst[i * 4 + 2] = src[i * 3 + 2];
                dst[i * 4 + 3] = 0xFFFF;
            }
        }
        else if (pixelFormat == RGBA8)
        {
            // Convert BGRA -> RGBA
            const uint8_t* src = imgBuffer;
            uint8_t* dst = fb.scanline<uint8_t>(0);
            size_t numPixels = static_cast<size_t>(w) * static_cast<size_t>(h);
            for (size_t i = 0; i < numPixels; ++i)
            {
                dst[i * 4 + 0] = src[i * 4 + 2];
                dst[i * 4 + 1] = src[i * 4 + 1];
                dst[i * 4 + 2] = src[i * 4 + 0];
                dst[i * 4 + 3] = src[i * 4 + 3];
            }
        }
        else
        {
            // RGB16 or RGB_HALF: direct copy into FB
            size_t copyBytes = std::min(memNeeded, fb.allocSize());
            std::memcpy(fb.scanline<unsigned char>(0), imgBuffer, copyBytes);
        }

        free(imgBuffer - adjusted);

        fb.setIdentifier("");
        identifier(frame, fb.idstream());
        fb.addAttribute(new StringAttribute("File", m_filename));
        fb.addAttribute(new StringAttribute("ColorSpace/Primaries", ColorSpace::RedWideGamut()));
        fb.addAttribute(new StringAttribute("ColorSpace/TransferFunction", ColorSpace::RedLogFilm()));
        fb.addAttribute(new StringAttribute("RED/Acceleration", decodedOnGpu ? "Metal GPU" : "CPU"));
        fb.addAttribute(new StringAttribute("RED/Resolution", (m_impl->clipResolution == FULL_RES)      ? "Full (1:1)"
                                                              : (m_impl->clipResolution == HALF_RES)    ? "Half (1:2)"
                                                              : (m_impl->clipResolution == QUARTER_RES) ? "Quarter (1:4)"
                                                                                                        : "Eighth (1:8)"));
        fb.addAttribute(new StringAttribute("RED/ColorScience", m_impl->colorScience));
        fb.addAttribute(new IntAttribute("RED/FrameIndex", static_cast<int>(videoFrameNo)));
        fb.addAttribute(new IntAttribute("RED/TotalFrames", static_cast<int>(m_impl->frameCount)));
        fb.addAttribute(new StringAttribute("RED/SDKVersion", R3DSDK::GetSdkVersion()));
    }

    void MovieRED::identifiersAtFrame(const ReadRequest& request, IdentifierVector& ids)
    {
        int frame = request.frame;
        ostringstream str;
        identifier(frame, str);
        ids.resize(1);
        ids.front() = str.str();
    }

    void MovieRED::identifier(int frame, ostream& o)
    {
        if (frame < m_info.start)
            frame = m_info.start;
        if (frame > m_info.end)
            frame = m_info.end;
        o << frame << ":" << m_filename;
    }

    //----------------------------------------------------------------------

    MovieREDIO::MovieREDIO()
        : MovieIO("MovieRED", "v1")
    {
        StringPairVector video;
        StringPairVector audio;
        unsigned int capabilities = MovieIO::MovieRead | MovieIO::AttributeRead;
        addType("r3d", "RED Cinema Camera Movie", capabilities, video, audio);
        addType("R3D", "RED Cinema Camera Movie", capabilities, video, audio);
    }

    MovieREDIO::~MovieREDIO() {}

    std::string MovieREDIO::about() const { return "RED Cinema Camera (R3D) Movie Reader"; }

    MovieReader* MovieREDIO::movieReader() const { return new MovieRED(); }

    MovieWriter* MovieREDIO::movieWriter() const { return nullptr; }

    void MovieREDIO::getMovieInfo(const std::string& filename, MovieInfo& info) const
    {
        MovieRED reader;
        Movie::ReadRequest request;
        reader.preloadOpen(filename, request);
        info = reader.info();
    }

} // namespace TwkMovie
