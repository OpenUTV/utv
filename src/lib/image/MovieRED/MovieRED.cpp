//******************************************************************************
// Copyright (c) 2026 Makai Systems and OpenUTV Contributors. All rights reserved.
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
#include <R3DSDKMetadata.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <iomanip>
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

    static const char* initializeStatusString(R3DSDK::InitializeStatus st)
    {
        switch (st)
        {
        case R3DSDK::ISInitializeOK:
            return "OK";
        case R3DSDK::ISLibraryNotLoaded:
            return "Library not loaded";
        case R3DSDK::ISR3DSDKLibraryNotFound:
            return "R3DSDK library not found";
        case R3DSDK::ISRedCudaLibraryNotFound:
            return "RedCuda library not found";
        case R3DSDK::ISRedOpenCLLibraryNotFound:
            return "RedOpenCL library not found";
        case R3DSDK::ISR3DDecoderLibraryNotFound:
            return "R3DDecoder library not found";
        case R3DSDK::ISRedMetalLibraryNotFound:
            return "RedMetal library not found";
        case R3DSDK::ISLibraryVersionMismatch:
            return "Library version mismatch (SDK and dynamic library versions must match)";
        case R3DSDK::ISInvalidR3DSDKLibrary:
            return "Invalid R3DSDK library";
        case R3DSDK::ISInvalidRedCudaLibrary:
            return "Invalid RedCuda library";
        case R3DSDK::ISInvalidRedOpenCLLibrary:
            return "Invalid RedOpenCL library";
        case R3DSDK::ISInvalidR3DDecoderLibrary:
            return "Invalid R3DDecoder library";
        case R3DSDK::ISInvalidRedMetalLibrary:
            return "Invalid RedMetal library";
        case R3DSDK::ISRedCudaLibraryInitializeFailed:
            return "RedCuda initialization failed";
        case R3DSDK::ISRedOpenCLLibraryInitializeFailed:
            return "RedOpenCL initialization failed";
        case R3DSDK::ISR3DDecoderLibraryInitializeFailed:
            return "R3DDecoder initialization failed";
        case R3DSDK::ISR3DSDKLibraryInitializeFailed:
            return "R3DSDK library initialization failed";
        case R3DSDK::ISRedMetalLibraryInitializeFailed:
            return "RedMetal initialization failed";
        case R3DSDK::ISInvalidPath:
            return "Invalid path";
        case R3DSDK::ISInternalError:
            return "Internal error";
        case R3DSDK::ISMetalNotAvailable:
            return "Metal not available";
        case R3DSDK::ISCudaNotAvailable:
            return "CUDA not available";
        default:
            return "Unknown status";
        }
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

        if (const char* home = getenv("HOME"))
        {
#if defined(__APPLE__)
            searchDirs.push_back(std::string(home) + "/Library/Application Support/OpenUTV/RED");
#elif defined(__linux__)
            searchDirs.push_back(std::string(home) + "/.local/share/openutv/red");
#endif
        }
#if defined(_WIN32)
        if (const char* appData = getenv("APPDATA"))
        {
            searchDirs.push_back(std::string(appData) + "\\OpenUTV\\RED");
        }
#endif

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
        searchDirs.push_back("/Applications/REDCINE-X Professional/RED PLAYER.app/Contents/MacOS");
        searchDirs.push_back("/Applications/REDCINE-X Professional/REDCINE-X PRO.app/Contents/MacOS");
        searchDirs.push_back("/Applications/RED PLAYER.app/Contents/MacOS");
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
        searchDirs.push_back("C:/Program Files/RED/RED PLAYER");
        searchDirs.push_back("C:/Program Files/RED DIGITAL CINEMA/REDCINE-X PRO");
        searchDirs.push_back("C:/Program Files/RED DIGITAL CINEMA/RED PLAYER");
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
                    R3DSDK::FinalizeSdk();
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
                else
                {
                    std::cerr << "WARNING: Found RED dynamic library in " << dir << ", but InitializeSdk failed (" << st << ": "
                              << initializeStatusString(st) << ")" << std::endl;
                    if (st == R3DSDK::ISLibraryVersionMismatch)
                    {
                        std::cerr << "WARNING: OpenUTV was built against R3D SDK 9.2.1. The dynamic library in '" << dir
                                  << "' is an incompatible version. "
                                  << "Set RED_SDK_PATH or place R3D SDK 9.2.1 Redistributable libraries in application search paths."
                                  << std::endl;
                    }
                    R3DSDK::FinalizeSdk();
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

    static std::string getMetaString(const R3DSDK::Clip* clip, const char* key)
    {
        if (!clip || !clip->MetadataExists(key))
            return std::string();
        return clip->MetadataItemAsString(key);
    }

    static void setNonEmptyAttr(TwkFB::FrameBuffer& fb, const std::string& key, const std::string& val)
    {
        if (!val.empty())
        {
            fb.newAttribute(key, val);
        }
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
                                          "Please install RED PLAYER from https://www.red.com/downloads or set RED_SDK_PATH.");
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

        // Populate clip-level metadata on m_info.proxy
        TwkFB::FrameBuffer& proxy = m_info.proxy;
        proxy.newAttribute("File", m_filename);
        proxy.newAttribute("Container", std::string("RED Digital Cinema (R3D)"));

        std::ostringstream durStr;
        durStr << m_impl->frameCount << " frames (" << std::fixed << std::setprecision(2)
               << (static_cast<double>(m_impl->frameCount) / m_impl->fps) << "s @ " << m_impl->fps << " fps)";
        proxy.newAttribute("Duration", durStr.str());

        std::ostringstream fpsStr;
        fpsStr << m_impl->fps;
        proxy.newAttribute("FPS", fpsStr.str());

        std::ostringstream resStr;
        resStr << m_impl->fullWidth << "x" << m_impl->fullHeight;
        proxy.newAttribute("Resolution", resStr.str());

        proxy.newAttribute("ColorSpace/Primaries", ColorSpace::RedWideGamut());
        proxy.newAttribute("ColorSpace/TransferFunction", ColorSpace::RedLogFilm());
        proxy.newAttribute("RED/ColorScience", m_impl->colorScience);
        proxy.newAttribute("RED/SDKVersion", std::string(R3DSDK::GetSdkVersion()));
        proxy.newAttribute("Make", std::string("RED Digital Cinema"));
        proxy.newAttribute("Camera/Manufacturer", std::string("RED Digital Cinema"));

        // Camera
        std::string camModel = getMetaString(m_impl->clip.get(), R3DSDK::RMD_CAMERA_MODEL);
        std::string camPin = getMetaString(m_impl->clip.get(), R3DSDK::RMD_CAMERA_PIN);
        std::string camId = getMetaString(m_impl->clip.get(), R3DSDK::RMD_CAMERA_ID);
        std::string camFirmware = getMetaString(m_impl->clip.get(), R3DSDK::RMD_CAMERA_FIRMWARE_VERSION);
        std::string sensorName = getMetaString(m_impl->clip.get(), R3DSDK::RMD_SENSOR_NAME);
        std::string sensorId = getMetaString(m_impl->clip.get(), R3DSDK::RMD_SENSOR_ID);

        setNonEmptyAttr(proxy, "Model", camModel);
        setNonEmptyAttr(proxy, "Software", camFirmware);
        setNonEmptyAttr(proxy, "Camera/Model", camModel);
        setNonEmptyAttr(proxy, "Camera/PIN", camPin);
        setNonEmptyAttr(proxy, "Camera/ID", camId);
        setNonEmptyAttr(proxy, "Camera/Firmware", camFirmware);
        setNonEmptyAttr(proxy, "Camera/Sensor", sensorName);
        setNonEmptyAttr(proxy, "Camera/SensorID", sensorId);

        // Lens
        std::string lensName = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LENS_NAME);
        std::string lensBrand = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LENS_BRAND);
        std::string lensFocal = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LENS_FOCAL_LENGTH);
        std::string lensAperture = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LENS_APERTURE_LABEL);
        std::string lensFocusDist = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LENS_FOCUS_DISTANCE);
        std::string lensMount = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LENS_MOUNT);
        std::string lensSerial = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LENS_SERIAL_NUMBER);

        setNonEmptyAttr(proxy, "LensModel", !lensName.empty() ? lensName : lensBrand);
        setNonEmptyAttr(proxy, "Lens/Name", lensName);
        setNonEmptyAttr(proxy, "Lens/Brand", lensBrand);
        if (!lensFocal.empty() && lensFocal != "0")
        {
            proxy.newAttribute("FocalLength", lensFocal + " mm");
            proxy.newAttribute("Lens/FocalLength", lensFocal + " mm");
        }
        if (!lensAperture.empty())
        {
            proxy.newAttribute("FNumber", lensAperture);
            proxy.newAttribute("Lens/Aperture", lensAperture);
        }
        if (!lensFocusDist.empty() && lensFocusDist != "0" && lensFocusDist != "4294967295")
        {
            proxy.newAttribute("Lens/FocusDistance", lensFocusDist + " mm");
        }
        setNonEmptyAttr(proxy, "Lens/Mount", lensMount);
        setNonEmptyAttr(proxy, "Lens/SerialNumber", lensSerial);

        // Exposure
        std::string iso = getMetaString(m_impl->clip.get(), R3DSDK::RMD_ISO);
        std::string shutterDeg = getMetaString(m_impl->clip.get(), R3DSDK::RMD_SHUTTER_DEGREES);
        std::string shutterFrac = getMetaString(m_impl->clip.get(), R3DSDK::RMD_SHUTTER_FRACTIONS);
        std::string expTime = getMetaString(m_impl->clip.get(), R3DSDK::RMD_EXPOSURE_TIME);

        setNonEmptyAttr(proxy, "ISO", iso);
        setNonEmptyAttr(proxy, "Exposure/ISO", iso);
        if (!shutterDeg.empty())
            proxy.newAttribute("Exposure/ShutterDegrees", shutterDeg + "°");
        if (!shutterFrac.empty() && shutterFrac != "0")
        {
            std::string speedStr = "1/" + shutterFrac + " s";
            proxy.newAttribute("ExposureTime", speedStr);
            proxy.newAttribute("Exposure/ShutterSpeed", speedStr);
        }
        else if (!expTime.empty() && expTime != "0")
        {
            proxy.newAttribute("ExposureTime", expTime + " µs");
        }
        if (!expTime.empty())
            proxy.newAttribute("Exposure/ExposureTime", expTime + " µs");

        // Color
        std::string kelvin = getMetaString(m_impl->clip.get(), R3DSDK::RMD_WHITE_BALANCE_KELVIN);
        std::string tint = getMetaString(m_impl->clip.get(), R3DSDK::RMD_WHITE_BALANCE_TINT);
        if (!kelvin.empty())
        {
            std::string wbStr = kelvin + " K";
            if (!tint.empty())
                wbStr += " (Tint " + tint + ")";
            proxy.newAttribute("WhiteBalance", wbStr);
            proxy.newAttribute("Color/WhiteBalanceKelvin", kelvin + " K");
        }
        setNonEmptyAttr(proxy, "Color/WhiteBalanceTint", tint);
        proxy.newAttribute("Color/ColorScience", m_impl->colorScience);

        // Production / Reel
        std::string reel = getMetaString(m_impl->clip.get(), R3DSDK::RMD_REEL_ID);
        std::string reelFull = getMetaString(m_impl->clip.get(), R3DSDK::RMD_REEL_ID_FULL);
        std::string clipId = getMetaString(m_impl->clip.get(), R3DSDK::RMD_CLIP_ID);
        std::string clipUuid = getMetaString(m_impl->clip.get(), R3DSDK::RMD_CLIP_UUID);
        std::string redcode = getMetaString(m_impl->clip.get(), R3DSDK::RMD_REDCODE);
        std::string resFormat = getMetaString(m_impl->clip.get(), R3DSDK::RMD_RESOLUTION_FORMAT_NAME);
        std::string recFps = getMetaString(m_impl->clip.get(), R3DSDK::RMD_RECORD_FRAMERATE);
        std::string origFilename = getMetaString(m_impl->clip.get(), R3DSDK::RMD_ORIGINAL_FILENAME);
        std::string wavFilename = getMetaString(m_impl->clip.get(), R3DSDK::RMD_WAV_FILENAME);

        setNonEmptyAttr(proxy, "Production/Reel", reel);
        setNonEmptyAttr(proxy, "Production/ReelFull", reelFull);
        setNonEmptyAttr(proxy, "Production/ClipID", clipId);
        setNonEmptyAttr(proxy, "Production/ClipUUID", clipUuid);
        setNonEmptyAttr(proxy, "Production/REDCODE", redcode);
        setNonEmptyAttr(proxy, "Production/ResolutionFormat", resFormat);
        if (!recFps.empty())
            proxy.newAttribute("Production/RecordFramerate", recFps + " fps");
        std::ostringstream prjFpsStr;
        prjFpsStr << m_impl->fps << " fps";
        proxy.newAttribute("Production/ProjectFramerate", prjFpsStr.str());
        setNonEmptyAttr(proxy, "Production/OriginalFilename", origFilename);
        setNonEmptyAttr(proxy, "Production/WavFilename", wavFilename);

        setNonEmptyAttr(proxy, "Production/Scene", getMetaString(m_impl->clip.get(), R3DSDK::RMD_USER_SCENE));
        setNonEmptyAttr(proxy, "Production/Shot", getMetaString(m_impl->clip.get(), R3DSDK::RMD_USER_SHOT));
        setNonEmptyAttr(proxy, "Production/Take", getMetaString(m_impl->clip.get(), R3DSDK::RMD_USER_TAKE));
        setNonEmptyAttr(proxy, "Production/Director", getMetaString(m_impl->clip.get(), R3DSDK::RMD_USER_DIRECTOR));
        setNonEmptyAttr(proxy, "Production/DP", getMetaString(m_impl->clip.get(), R3DSDK::RMD_USER_DIRECTOR_OF_PHOTOGRAPHY));
        setNonEmptyAttr(proxy, "Production/Copyright", getMetaString(m_impl->clip.get(), R3DSDK::RMD_USER_COPYRIGHT));

        // Date / Time
        std::string localDate = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LOCAL_DATE);
        std::string localTime = getMetaString(m_impl->clip.get(), R3DSDK::RMD_LOCAL_TIME);
        std::string gmtDate = getMetaString(m_impl->clip.get(), R3DSDK::RMD_GMT_DATE);
        std::string gmtTime = getMetaString(m_impl->clip.get(), R3DSDK::RMD_GMT_TIME);
        std::string dateTimeStr =
            !localDate.empty() ? (localDate + " " + localTime) : (!gmtDate.empty() ? (gmtDate + " " + gmtTime + " GMT") : "");
        setNonEmptyAttr(proxy, "DateTime", dateTimeStr);
        setNonEmptyAttr(proxy, "Date/Captured", dateTimeStr);

        // Timecode
        std::string startAbsTc = getMetaString(m_impl->clip.get(), R3DSDK::RMD_START_ABSOLUTE_TIMECODE);
        std::string startEdgeTc = getMetaString(m_impl->clip.get(), R3DSDK::RMD_START_EDGE_TIMECODE);
        std::string startTc;
        {
            std::lock_guard<std::mutex> lock(m_impl->clipMutex);
            const char* ctc = m_impl->clip->Timecode(0);
            if (ctc && ctc[0] != '\0')
                startTc = ctc;
        }
        if (startTc.empty())
            startTc = !startAbsTc.empty() ? startAbsTc : startEdgeTc;

        setNonEmptyAttr(proxy, "Timecode", startTc);
        setNonEmptyAttr(proxy, "Timecode/Start", startTc);
        setNonEmptyAttr(proxy, "Timecode/Absolute", startAbsTc);
        setNonEmptyAttr(proxy, "Timecode/Edge", startEdgeTc);
        std::ostringstream tcRateStr;
        tcRateStr << m_impl->clip->TimecodeFramerate();
        proxy.newAttribute("Timecode/FrameRate", tcRateStr.str());

        // Enumerate all raw clip metadata under RED/
        size_t metaCount = m_impl->clip->MetadataCount();
        for (size_t i = 0; i < metaCount; ++i)
        {
            std::string key = m_impl->clip->MetadataItemKey(i);
            std::string val = m_impl->clip->MetadataItemAsString(i);
            if (!key.empty() && !val.empty())
            {
                proxy.newAttribute("RED/" + key, val);
            }
        }
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

        R3DSDK::Metadata frameMeta;
        bool decodedOnGpu = false;
#if defined(__APPLE__)
        if (m_impl->useGpu && REDMetalGpu::isAvailable() && pixelFormat != RGBA8)
        {
            decodedOnGpu =
                REDMetalGpu::debayerFrame(m_impl->clip.get(), videoFrameNo, jobMode, jobPixelType, imgBuffer, memNeeded, &frameMeta);
        }
#endif

        if (!decodedOnGpu)
        {
            R3DSDK::VideoDecodeJob job;
            job.Mode = jobMode;
            job.PixelType = (pixelFormat == RGBA8) ? R3DSDK::PixelType_8Bit_BGRA_Interleaved : jobPixelType;
            job.OutputBuffer = imgBuffer;
            job.OutputBufferSize = memNeeded;
            job.OutputFrameMetadata = &frameMeta;

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

        // Copy clip-level metadata from m_info.proxy
        m_info.proxy.copyAttributesTo(&fb);

        fb.setIdentifier("");
        identifier(frame, fb.idstream());
        fb.newAttribute("File", m_filename);
        fb.newAttribute("ColorSpace/Primaries", ColorSpace::RedWideGamut());
        fb.newAttribute("ColorSpace/TransferFunction", ColorSpace::RedLogFilm());
        fb.newAttribute("RED/Acceleration", decodedOnGpu ? std::string("Metal GPU") : std::string("CPU"));
        fb.newAttribute("RED/Resolution", (m_impl->clipResolution == FULL_RES)      ? std::string("Full (1:1)")
                                          : (m_impl->clipResolution == HALF_RES)    ? std::string("Half (1:2)")
                                          : (m_impl->clipResolution == QUARTER_RES) ? std::string("Quarter (1:4)")
                                                                                    : std::string("Eighth (1:8)"));
        fb.newAttribute("RED/ColorScience", m_impl->colorScience);
        fb.newAttribute("RED/FrameIndex", static_cast<int>(videoFrameNo));
        fb.newAttribute("RED/TotalFrames", static_cast<int>(m_impl->frameCount));
        fb.newAttribute("RED/SDKVersion", std::string(R3DSDK::GetSdkVersion()));

        // Per-frame timecodes
        std::string frameTc;
        std::string frameAbsTc;
        std::string frameEdgeTc;
        {
            std::lock_guard<std::mutex> lock(m_impl->clipMutex);
            const char* ctc = m_impl->clip->Timecode(videoFrameNo);
            if (ctc && ctc[0] != '\0')
                frameTc = ctc;
            const char* atc = m_impl->clip->AbsoluteTimecode(videoFrameNo);
            if (atc && atc[0] != '\0')
                frameAbsTc = atc;
            const char* etc = m_impl->clip->EdgeTimecode(videoFrameNo);
            if (etc && etc[0] != '\0')
                frameEdgeTc = etc;
        }

        if (frameMeta.MetadataCount() == 0)
        {
            std::lock_guard<std::mutex> lock(m_impl->clipMutex);
            m_impl->clip->GetFrameMetadata(frameMeta, videoFrameNo);
        }

        if (frameMeta.MetadataExists(R3DSDK::RMD_FRAME_ABSOLUTE_TIMECODE))
        {
            frameAbsTc = frameMeta.MetadataItemAsString(R3DSDK::RMD_FRAME_ABSOLUTE_TIMECODE);
            if (frameTc.empty())
                frameTc = frameAbsTc;
        }
        if (frameMeta.MetadataExists(R3DSDK::RMD_FRAME_EDGE_TIMECODE))
        {
            frameEdgeTc = frameMeta.MetadataItemAsString(R3DSDK::RMD_FRAME_EDGE_TIMECODE);
            if (frameTc.empty())
                frameTc = frameEdgeTc;
        }

        if (!frameTc.empty())
            fb.newAttribute("Timecode", frameTc);
        if (!frameAbsTc.empty())
            fb.newAttribute("Timecode/Absolute", frameAbsTc);
        if (!frameEdgeTc.empty())
            fb.newAttribute("Timecode/Edge", frameEdgeTc);

        if (frameMeta.MetadataExists(R3DSDK::RMD_FRAME_TIMESTAMP))
        {
            fb.newAttribute("Time/Timestamp", frameMeta.MetadataItemAsString(R3DSDK::RMD_FRAME_TIMESTAMP) + " µs");
        }
        if (frameMeta.MetadataExists(R3DSDK::RMD_FRAME_PTP_TIMESTAMP))
        {
            fb.newAttribute("Time/PTPTimestamp", frameMeta.MetadataItemAsString(R3DSDK::RMD_FRAME_PTP_TIMESTAMP) + " ns");
        }

        size_t fMetaCount = frameMeta.MetadataCount();
        for (size_t i = 0; i < fMetaCount; ++i)
        {
            std::string key = frameMeta.MetadataItemKey(i);
            std::string val = frameMeta.MetadataItemAsString(i);
            if (!key.empty() && !val.empty())
            {
                fb.newAttribute("RED/" + key, val);
            }
        }
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
        o << frame << ":" << (m_impl ? static_cast<int>(m_impl->clipResolution) : 0) << ":" << (m_impl && m_impl->useGpu ? "gpu" : "cpu")
          << ":" << m_filename;
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
