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
#include <QtCore/QProcessEnvironment>
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
        info.name = tr("FFmpeg Multimedia Engine - v6.x/v7.x (Full)");
        info.isAvailable = true;
        info.isSupercharged = false;
        info.isShadowed = false;
        info.helpUrl = "https://www.gyan.dev/ffmpeg/builds/";

        // 1. Run 'ffmpeg -version' to inspect active configuration flags
        QString ffmpegOutput;
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        QString currentPath = env.value("PATH");
#if defined(PLATFORM_DARWIN)
        if (!currentPath.contains("/opt/homebrew/bin"))
        {
            currentPath = "/opt/homebrew/bin:/usr/local/bin:" + currentPath;
            env.insert("PATH", currentPath);
        }
#elif defined(__linux__)
        if (!currentPath.contains("/home/linuxbrew/.linuxbrew/bin"))
        {
            currentPath = "/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:" + currentPath;
            env.insert("PATH", currentPath);
        }
#endif

        QProcess process;
        process.setProcessEnvironment(env);
        process.start("ffmpeg", QStringList() << "-version");
        if (process.waitForFinished(500))
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
                    p2.setProcessEnvironment(env);
                    p2.start(b, QStringList() << "-version");
                    if (p2.waitForFinished(500))
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
        info.name = tr("Blackmagic RAW (BRAW) - SDK v4.2+");
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
            info.details = tr("Detected Blackmagic RAW runtime at: %1 (SDK v4.2+ / Resolve 19+ compatible)").arg(foundPath);
            info.actionText = "";
        }
        else
        {
            info.statusBadge = tr("Not Installed");
            info.details = tr("Requires Blackmagic RAW SDK v4.2+ (or DaVinci Resolve 19+). Install DaVinci Resolve or the free Blackmagic "
                              "RAW Player & SDK.");
            info.actionText = tr("Get Blackmagic RAW (Free)");
        }

        m_codecs.push_back(info);
    }

    void RvCodecManager::probeRED()
    {
        ThirdPartyCodecInfo info;
        info.id = "red";
        info.name = tr("RED Digital Cinema (R3D) - SDK v9.2+");
        info.isAvailable = false;
        info.isSupercharged = false;
        info.isShadowed = false;
        info.helpUrl = "https://www.red.com/download/r3d-sdk";
        info.localFolderPath = getRedFolderPath();

        QStringList candidateFiles = {
#if defined(PLATFORM_DARWIN)
            info.localFolderPath + "/REDR3D.dylib",
            info.localFolderPath + "/REDDecoder.dylib",
            info.localFolderPath + "/libR3DSDK.dylib",
            info.localFolderPath + "/R3DSDK.framework",
            "/Applications/REDCINE-X Professional/REDCINE-X PRO.app/Contents/MacOS/REDR3D.dylib",
            "/Applications/REDCINE-X Professional/RED PLAYER.app/Contents/MacOS/REDR3D.dylib",
            "/usr/local/lib/REDR3D.dylib",
            "/usr/local/lib/libR3DSDK.dylib",
            "/opt/homebrew/lib/REDR3D.dylib"
#elif defined(PLATFORM_WINDOWS)
            info.localFolderPath + "/REDR3D-x64.dll",
            info.localFolderPath + "/REDR3D.dll",
            info.localFolderPath + "/REDDecoder-x64.dll",
            info.localFolderPath + "/R3DSDK.dll",
            "C:/Program Files/OpenUTV/RED/REDR3D-x64.dll",
            "C:/Program Files/OpenUTV/RED/R3DSDK.dll",
            "C:/Program Files/REDCINE-X PRO/REDR3D-x64.dll",
            "C:/Program Files/REDCINE-X Professional/REDR3D-x64.dll",
            "C:/Program Files/RED/REDR3D-x64.dll"
#else
            info.localFolderPath + "/REDR3D-x64.so",
            info.localFolderPath + "/REDDecoder-x64.so",
            info.localFolderPath + "/libREDR3D-x64.so",
            info.localFolderPath + "/libR3DSDK.so",
            "/usr/lib/REDR3D-x64.so",
            "/usr/local/lib/REDR3D-x64.so",
            "/usr/lib64/REDR3D-x64.so"
#endif
        };

        const char* envNames[] = {"RED_SDK_PATH", "R3DSDK_DIR", "RV_DEPS_RED_SDK_DIR"};
        for (const char* envName : envNames)
        {
            const char* envVal = getenv(envName);
            if (envVal && strlen(envVal) > 0)
            {
                QString base(envVal);
#if defined(PLATFORM_DARWIN)
                candidateFiles.prepend(base + "/Redistributable/mac/REDR3D.dylib");
                candidateFiles.prepend(base + "/REDR3D.dylib");
                candidateFiles.prepend(base + "/libR3DSDK.dylib");
#elif defined(PLATFORM_WINDOWS)
                candidateFiles.prepend(base + "/Redistributable/win/REDR3D-x64.dll");
                candidateFiles.prepend(base + "/REDR3D-x64.dll");
                candidateFiles.prepend(base + "/R3DSDK.dll");
#else
                candidateFiles.prepend(base + "/Redistributable/linux/REDR3D-x64.so");
                candidateFiles.prepend(base + "/REDR3D-x64.so");
                candidateFiles.prepend(base + "/libR3DSDK.so");
#endif
            }
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
            info.details = tr("Detected RED R3D runtime at: %1 (SDK v9.2.1 compatible)").arg(foundFile);
            info.actionText = tr("Open RED Folder");
        }
        else
        {
            info.statusBadge = tr("Not Installed");
            info.details = tr("Requires RED R3D SDK v9.2.1+ (or REDCINE-X Professional). Place REDR3D.dylib into OpenUTV's RED folder.");
            info.actionText = tr("Download RED SDK (Free)");
        }

        m_codecs.push_back(info);
    }

    void RvCodecManager::probeNDI()
    {
        ThirdPartyCodecInfo info;
        info.id = "ndi";
        info.name = tr("NDI (Network Video Streamer) - SDK v5/v6");
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
            info.details = tr("Detected NDI Runtime at: %1 (NDI 5 / NDI 6 compatible)").arg(foundFile);
            info.actionText = "";
        }
        else
        {
            info.statusBadge = tr("Not Installed");
            info.details = tr("Requires NDI SDK v5.x or v6.x runtime. Install free NDI Tools to enable real-time IP video streaming.");
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
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        QString currentPath = env.value("PATH");
#if defined(PLATFORM_DARWIN)
        currentPath = "/opt/homebrew/bin:/usr/local/bin:" + currentPath;
#elif defined(__linux__)
        currentPath = "/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:" + currentPath;
#endif
        env.insert("PATH", currentPath);
        proc.setProcessEnvironment(env);

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
