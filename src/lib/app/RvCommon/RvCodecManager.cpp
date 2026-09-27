//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#include <RvCommon/RvCodecManager.h>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QProcess>
#include <QtCore/QStandardPaths>
#include <QtGui/QDesktopServices>
#include <QtCore/QUrl>
#include <QtCore/QDebug>

#include <cstdlib>

namespace Rv
{

    RvCodecManager* RvCodecManager::instance()
    {
        static RvCodecManager s_instance;
        return &s_instance;
    }

    RvCodecManager::RvCodecManager(QObject* parent)
        : QObject(parent)
    {
        probeAll();
    }

    void RvCodecManager::probeAll()
    {
        m_codecs.clear();

        probeFFmpeg();
        probeBRAW();
        probeRED();
        probeNDI();
        probeAppleCodecs();

        Q_EMIT statusUpdated();
    }

    const std::vector<ThirdPartyCodecInfo>& RvCodecManager::codecs() const { return m_codecs; }

    const ThirdPartyCodecInfo* RvCodecManager::getCodec(const QString& id) const
    {
        for (const auto& c : m_codecs)
        {
            if (c.id == id)
            {
                return &c;
            }
        }
        return nullptr;
    }

    bool RvCodecManager::isFFmpegSupercharged() const
    {
        const ThirdPartyCodecInfo* c = getCodec("ffmpeg");
        return c && c->isSupercharged;
    }

    bool RvCodecManager::isFFmpegShadowed() const
    {
        const ThirdPartyCodecInfo* c = getCodec("ffmpeg");
        return c && c->isShadowed;
    }

    void RvCodecManager::probeFFmpeg()
    {
        ThirdPartyCodecInfo info;
        info.id = "ffmpeg";
        info.name = tr("FFmpeg Multimedia Engine");
        info.isAvailable = true;
        info.isSupercharged = false;
        info.isShadowed = false;
        info.helpUrl = "https://www.gyan.dev/ffmpeg/builds/";

        // 1. Run 'ffmpeg -version' to inspect active configuration flags
        QString ffmpegOutput;
        QProcess process;
        process.start("ffmpeg", QStringList() << "-version");
        if (process.waitForFinished(1500))
        {
            ffmpegOutput = QString::fromUtf8(process.readAllStandardOutput());
        }

        if (ffmpegOutput.isEmpty())
        {
            // Try homebrew bin or common locations if not in GUI PATH
            QStringList candidateBins = {"/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "C:/Program Files/OpenUTVDeps/bin/ffmpeg.exe",
                                         "C:/Program Files/OpenUTVDeps/installed/x64-windows/bin/ffmpeg.exe"};
            for (const auto& b : candidateBins)
            {
                if (QFile::exists(b))
                {
                    QProcess p2;
                    p2.start(b, QStringList() << "-version");
                    if (p2.waitForFinished(1500))
                    {
                        ffmpegOutput = QString::fromUtf8(p2.readAllStandardOutput());
                        if (!ffmpegOutput.isEmpty())
                        {
                            break;
                        }
                    }
                }
            }
        }

        // Check if configuration has libx265 / nonfree
        if (ffmpegOutput.contains("enable-libx265") || ffmpegOutput.contains("libx265") || ffmpegOutput.contains("enable-nonfree"))
        {
            info.isSupercharged = true;
        }

        // 2. Check if ffmpeg-full is installed on macOS or Linux
        bool fullInstalled = false;
        QString fullPath;
        QStringList fullCandidates = {"/opt/homebrew/opt/ffmpeg-full", "/usr/local/opt/ffmpeg-full",
                                      "/home/linuxbrew/.linuxbrew/opt/ffmpeg-full"};

        for (const auto& p : fullCandidates)
        {
            if (QDir(p).exists())
            {
                fullInstalled = true;
                fullPath = p;
                break;
            }
        }

        // 3. Determine status badge and action
#if defined(PLATFORM_DARWIN) || defined(__linux__)
        if (info.isSupercharged)
        {
            info.statusBadge = tr("Supercharged (Full Codecs)");
            info.details = tr("Active FFmpeg build includes H.265/HEVC, ProRes, AAC, and extended codecs.");
            info.actionText = "";
        }
        else if (fullInstalled)
        {
            // Installed but shadowed by regular ffmpeg!
            info.isShadowed = true;
            info.statusBadge = tr("Shadowed by Standard FFmpeg");
            info.details = tr("FFmpeg-Full is installed in %1, but regular FFmpeg is linked in PATH.").arg(fullPath);
            info.actionText = tr("Relink FFmpeg-Full");
        }
        else
        {
            info.statusBadge = tr("Standard (Basic Codecs)");
            info.details = tr("Standard FFmpeg active. Patent-encumbered decoders (H.265/HEVC, AAC, ProRes) require FFmpeg-Full.");
            info.actionText = tr("Install FFmpeg-Full (Homebrew)");
        }
#else
        // Windows
        if (info.isSupercharged)
        {
            info.statusBadge = tr("Supercharged (Full Codecs)");
            info.details = tr("Active FFmpeg build includes H.265/HEVC, ProRes, AAC, and extended codecs.");
            info.actionText = "";
        }
        else
        {
            info.statusBadge = tr("Standard (Basic Codecs)");
            info.details = tr("Standard OpenUTVDeps FFmpeg active. Unlock H.265/HEVC and extended codecs via Gyan.dev / Winget.");
            info.actionText = tr("Supercharge FFmpeg (Windows)...");
        }
#endif

        m_codecs.push_back(info);
    }

    void RvCodecManager::probeBRAW()
    {
        ThirdPartyCodecInfo info;
        info.id = "braw";
        info.name = tr("Blackmagic RAW (BRAW)");
        info.isAvailable = false;
        info.isSupercharged = false;
        info.isShadowed = false;
        info.helpUrl = "https://www.blackmagicdesign.com/support/family/professional-cameras";

        QStringList searchPaths = {
#if defined(PLATFORM_DARWIN)
            "/Applications/Blackmagic RAW/Blackmagic RAW Player.app", "/Applications/DaVinci Resolve/DaVinci Resolve.app",
            "/Applications/Blackmagic RAW/Blackmagic RAW SDK/Mac/Libraries", "/Library/Application Support/Blackmagic Design/Blackmagic RAW"
#elif defined(PLATFORM_WINDOWS)
            "C:/Program Files/Blackmagic Design/Blackmagic RAW", "C:/Program Files/Blackmagic Design/DaVinci Resolve"
#else
            "/usr/lib/libBlackmagicRawAPI.so", "/usr/local/lib/libBlackmagicRawAPI.so", "/opt/resolve/libs"
#endif
        };

        QString foundPath;
        for (const auto& p : searchPaths)
        {
            if (QDir(p).exists() || QFile::exists(p))
            {
                info.isAvailable = true;
                foundPath = p;
                break;
            }
        }

        if (info.isAvailable)
        {
            info.statusBadge = tr("Available (Ready for .braw playback)");
            info.details = tr("Detected runtime at: %1").arg(foundPath);
            info.actionText = "";
        }
        else
        {
            info.statusBadge = tr("Not Installed");
            info.details = tr("Install DaVinci Resolve or the free Blackmagic RAW Player & SDK to enable .braw playback.");
            info.actionText = tr("Get Blackmagic RAW (Free)");
        }

        m_codecs.push_back(info);
    }

    void RvCodecManager::probeRED()
    {
        ThirdPartyCodecInfo info;
        info.id = "red";
        info.name = tr("RED Digital Cinema (R3D)");
        info.isAvailable = false;
        info.isSupercharged = false;
        info.isShadowed = false;
        info.helpUrl = "https://www.red.com/download/r3d-sdk";
        info.localFolderPath = getRedFolderPath();

        QStringList candidateFiles = {
#if defined(PLATFORM_DARWIN)
            info.localFolderPath + "/libR3DSDK.dylib", info.localFolderPath + "/R3DSDK.framework", "/usr/local/lib/libR3DSDK.dylib"
#elif defined(PLATFORM_WINDOWS)
            info.localFolderPath + "/R3DSDK.dll", "C:/Program Files/OpenUTV/RED/R3DSDK.dll"
#else
            info.localFolderPath + "/libR3DSDK.so", "/usr/local/lib/libR3DSDK.so"
#endif
        };

        const char* env1 = getenv("RED_SDK_PATH");
        const char* env2 = getenv("R3DSDK_DIR");
        if (env1 && strlen(env1) > 0)
        {
            candidateFiles.prepend(QString(env1) + "/libR3DSDK.dylib");
            candidateFiles.prepend(QString(env1) + "/R3DSDK.dll");
            candidateFiles.prepend(QString(env1) + "/libR3DSDK.so");
        }
        if (env2 && strlen(env2) > 0)
        {
            candidateFiles.prepend(QString(env2) + "/libR3DSDK.dylib");
            candidateFiles.prepend(QString(env2) + "/R3DSDK.dll");
            candidateFiles.prepend(QString(env2) + "/libR3DSDK.so");
        }

        QString foundFile;
        for (const auto& f : candidateFiles)
        {
            if (QFile::exists(f) || QDir(f).exists())
            {
                info.isAvailable = true;
                foundFile = f;
                break;
            }
        }

        if (info.isAvailable)
        {
            info.statusBadge = tr("Available (Ready for .r3d playback)");
            info.details = tr("Detected R3D SDK runtime at: %1").arg(foundFile);
            info.actionText = tr("Open RED Folder");
        }
        else
        {
            info.statusBadge = tr("Not Installed");
            info.details = tr("Download the free RED R3D SDK from RED.com and place libraries in OpenUTV's RED directory.");
            info.actionText = tr("Download RED SDK (Free)");
        }

        m_codecs.push_back(info);
    }

    void RvCodecManager::probeNDI()
    {
        ThirdPartyCodecInfo info;
        info.id = "ndi";
        info.name = tr("NDI (Network Video Streamer)");
        info.isAvailable = false;
        info.isSupercharged = false;
        info.isShadowed = false;
        info.helpUrl = "https://ndi.video/tools/";

        QStringList candidateFiles = {
#if defined(PLATFORM_DARWIN)
            "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib", "/usr/local/lib/libndi.dylib", "/opt/homebrew/lib/libndi.dylib"
#elif defined(PLATFORM_WINDOWS)
            "C:/Program Files/NDI/NDI 5 Runtime/v5/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI 6 Runtime/v6/Processing.NDI.Lib.x64.dll", "C:/Program Files/NDI 5 SDK/Lib/x64/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI 6 SDK/Lib/x64/Processing.NDI.Lib.x64.dll"
#else
            "/usr/lib/libndi.so", "/usr/local/lib/libndi.so"
#endif
        };

        const char* ndiV5 = getenv("NDI_RUNTIME_DIR_V5");
        const char* ndiV6 = getenv("NDI_RUNTIME_DIR_V6");
        if (ndiV5 && strlen(ndiV5) > 0)
        {
            candidateFiles.prepend(QString(ndiV5) + "/Processing.NDI.Lib.x64.dll");
            candidateFiles.prepend(QString(ndiV5) + "/libndi.dylib");
            candidateFiles.prepend(QString(ndiV5) + "/libndi.so");
        }
        if (ndiV6 && strlen(ndiV6) > 0)
        {
            candidateFiles.prepend(QString(ndiV6) + "/Processing.NDI.Lib.x64.dll");
            candidateFiles.prepend(QString(ndiV6) + "/libndi.dylib");
            candidateFiles.prepend(QString(ndiV6) + "/libndi.so");
        }

        QString foundFile;
        for (const auto& f : candidateFiles)
        {
            if (QFile::exists(f))
            {
                info.isAvailable = true;
                foundFile = f;
                break;
            }
        }

        if (info.isAvailable)
        {
            info.statusBadge = tr("Available (IP Video Streaming Ready)");
            info.details = tr("Detected NDI Runtime at: %1").arg(foundFile);
            info.actionText = "";
        }
        else
        {
            info.statusBadge = tr("Not Installed");
            info.details = tr("Install free NDI Tools / NDI 5+ Runtime to stream and receive real-time video over IP networks.");
            info.actionText = tr("Get NDI Tools (Free)");
        }

        m_codecs.push_back(info);
    }

    void RvCodecManager::probeAppleCodecs()
    {
#if defined(PLATFORM_DARWIN)
        ThirdPartyCodecInfo info;
        info.id = "videotoolbox";
        info.name = tr("Apple VideoToolbox & ProRes");
        info.isAvailable = true;
        info.isSupercharged = true;
        info.isShadowed = false;
        info.statusBadge = tr("Hardware Accelerated");
        info.details = tr("Native Apple Silicon VideoToolbox H.264/HEVC and AVFoundation ProRes RAW decoding active.");
        info.actionText = "";
        info.helpUrl = "https://developer.apple.com/documentation/videotoolbox";
        m_codecs.push_back(info);
#endif
    }

    QString RvCodecManager::getRedFolderPath() const
    {
#if defined(PLATFORM_DARWIN)
        QString p = QDir::homePath() + "/Library/Application Support/OpenUTV/RED";
#elif defined(PLATFORM_WINDOWS)
        QString p = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/RED";
#else
        QString p = QDir::homePath() + "/.local/share/openutv/red";
#endif
        QDir d(p);
        if (!d.exists())
        {
            d.mkpath(".");
        }
        return p;
    }

    void RvCodecManager::openRedFolder()
    {
        QString path = getRedFolderPath();
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }

    bool RvCodecManager::relinkFFmpegFull(QString& outMessage)
    {
#if defined(PLATFORM_DARWIN) || defined(__linux__)
        QString cmd = "brew unlink ffmpeg-full && brew unlink ffmpeg && brew link --overwrite ffmpeg-full";
        QProcess proc;
        proc.start("sh", QStringList() << "-c" << cmd);
        if (!proc.waitForFinished(10000))
        {
            outMessage = tr("Relink command timed out.");
            return false;
        }

        QString out = QString::fromUtf8(proc.readAllStandardOutput());
        QString err = QString::fromUtf8(proc.readAllStandardError());

        if (proc.exitCode() == 0)
        {
            outMessage = tr("FFmpeg-Full relinked successfully!\n%1").arg(out);
            probeAll();
            return true;
        }
        else
        {
            outMessage = tr("Failed to relink FFmpeg-Full:\n%1\n%2").arg(out, err);
            return false;
        }
#else
        outMessage = tr("Relinking is only applicable on macOS/Linux with Homebrew.");
        return false;
#endif
    }

} // namespace Rv
