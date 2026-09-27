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
#include <QtCore/QSettings>
#include <QtCore/QDirIterator>

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
        info.name = tr("FFmpeg Multimedia Engine - v7.x–v9.x+ (Full)");
        info.isAvailable = true;
        info.isSupercharged = false;
        info.isShadowed = false;
        info.helpUrl = "https://www.gyan.dev/ffmpeg/builds/";

        QString activeBinaryPath;
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
#elif defined(PLATFORM_WINDOWS)
        QString localAppData = qEnvironmentVariable("LOCALAPPDATA");
        if (localAppData.isEmpty())
        {
            localAppData = QDir::homePath() + "/AppData/Local";
        }
        QString userProfile = qEnvironmentVariable("USERPROFILE");
        if (userProfile.isEmpty())
        {
            userProfile = QDir::homePath();
        }

        QString winGetLinks = localAppData + "/Microsoft/WinGet/Links";
        if (!currentPath.contains(winGetLinks, Qt::CaseInsensitive))
        {
            currentPath = winGetLinks + ";" + currentPath;
        }

        QString scoopShims = userProfile + "/scoop/shims";
        if (!currentPath.contains(scoopShims, Qt::CaseInsensitive))
        {
            currentPath = scoopShims + ";" + currentPath;
        }

        // Query registry to get freshly installed PATH entries (e.g. from winget or scoop while app is open)
        QSettings regUser("HKEY_CURRENT_USER\\Environment", QSettings::NativeFormat);
        QString userRegPath = regUser.value("Path").toString();
        if (!userRegPath.isEmpty())
        {
            currentPath = userRegPath + ";" + currentPath;
        }
        QSettings regSys("HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", QSettings::NativeFormat);
        QString sysRegPath = regSys.value("Path").toString();
        if (!sysRegPath.isEmpty())
        {
            currentPath = sysRegPath + ";" + currentPath;
        }
        env.insert("PATH", currentPath);
#endif

        QStringList candidateBins;

#if defined(PLATFORM_WINDOWS)
        // WinGet Links and Packages
        candidateBins << (localAppData + "/Microsoft/WinGet/Links/ffmpeg.exe");

        QDir winGetPackagesDir(localAppData + "/Microsoft/WinGet/Packages");
        if (winGetPackagesDir.exists())
        {
            QDirIterator it(winGetPackagesDir.absolutePath(), QStringList() << "ffmpeg.exe", QDir::Files, QDirIterator::Subdirectories);
            while (it.hasNext())
            {
                candidateBins << it.next();
            }
        }

        // Scoop and Chocolatey
        candidateBins << (userProfile + "/scoop/apps/ffmpeg-shared/current/bin/ffmpeg.exe");
        candidateBins << (userProfile + "/scoop/shims/ffmpeg.exe");
        candidateBins << "C:/ProgramData/chocolatey/bin/ffmpeg.exe";

        // Standard locations
        candidateBins << "C:/ffmpeg/bin/ffmpeg.exe";
        candidateBins << "C:/Program Files/ffmpeg/bin/ffmpeg.exe";
        candidateBins << "C:/Program Files/OpenUTVDeps/bin/ffmpeg.exe";
        candidateBins << "C:/Program Files/OpenUTVDeps/installed/x64-windows/bin/ffmpeg.exe";
#elif defined(PLATFORM_DARWIN)
        candidateBins << "/opt/homebrew/bin/ffmpeg" << "/usr/local/bin/ffmpeg";
#elif defined(__linux__)
        candidateBins << "/home/linuxbrew/.linuxbrew/bin/ffmpeg" << "/usr/bin/ffmpeg" << "/usr/local/bin/ffmpeg";
#endif

        // Also check findExecutable across refreshed PATH
        QString foundExec = QStandardPaths::findExecutable("ffmpeg", currentPath.split(QDir::listSeparator()));
        if (!foundExec.isEmpty() && !candidateBins.contains(foundExec))
        {
            candidateBins.prepend(foundExec);
        }

        auto checkFullBuild = [](const QString& binPath, const QString& output) -> bool
        {
            QString canonical = QFileInfo(binPath).canonicalFilePath();
            if (canonical.contains("ffmpeg-full", Qt::CaseInsensitive) || canonical.contains("full_build", Qt::CaseInsensitive)
                || canonical.contains("Gyan", Qt::CaseInsensitive) || canonical.contains("ffmpeg-shared", Qt::CaseInsensitive))
            {
                return true;
            }
            if (output.contains("Cellar/ffmpeg-full") || output.contains("opt/ffmpeg-full")
                || output.contains("full_build", Qt::CaseInsensitive) || output.contains("gyan.dev", Qt::CaseInsensitive)
                || output.contains("enable-libplacebo") || output.contains("enable-libxvid") || output.contains("enable-libtheora")
                || output.contains("enable-librav1e") || output.contains("enable-whisper") || output.contains("enable-libx265"))
            {
                return true;
            }
            return false;
        };

        QString ffmpegOutput;
        bool isFullBuild = false;

        // Iterate through candidates. If we find a full build, prefer it immediately!
        for (const auto& b : candidateBins)
        {
            if (QFile::exists(b))
            {
                QProcess proc;
                proc.setProcessEnvironment(env);
                proc.start(b, QStringList() << "-version");
                if (proc.waitForFinished(1000))
                {
                    QString out = QString::fromUtf8(proc.readAllStandardOutput());
                    if (!out.isEmpty())
                    {
                        bool full = checkFullBuild(b, out);
                        if (full)
                        {
                            activeBinaryPath = b;
                            ffmpegOutput = out;
                            isFullBuild = true;
                            break; // Found preferred full build!
                        }
                        else if (activeBinaryPath.isEmpty())
                        {
                            // Remember basic build as fallback
                            activeBinaryPath = b;
                            ffmpegOutput = out;
                        }
                    }
                }
            }
        }

        // 1. Extract detected version string (e.g. "9.0.2")
        QString detectedVersion;
        int verIdx = ffmpegOutput.indexOf("ffmpeg version ");
        if (verIdx != -1)
        {
            int start = verIdx + 15;
            int end = ffmpegOutput.indexOf(' ', start);
            if (end != -1)
            {
                detectedVersion = ffmpegOutput.mid(start, end - start).trimmed();
            }
        }

        info.isSupercharged = isFullBuild;

        // 2. Check if ffmpeg-full / Gyan Shared is installed on macOS, Linux, or Windows
        bool fullInstalled = false;
        QString fullPath;
#if defined(PLATFORM_DARWIN) || defined(__linux__)
        QStringList fullCandidates = {
            "/opt/homebrew/opt/ffmpeg-full", "/opt/homebrew/Cellar/ffmpeg-full",           "/usr/local/opt/ffmpeg-full",
            "/usr/local/Cellar/ffmpeg-full", "/home/linuxbrew/.linuxbrew/opt/ffmpeg-full", "/home/linuxbrew/.linuxbrew/Cellar/ffmpeg-full"};

        for (const auto& p : fullCandidates)
        {
            if (QDir(p).exists())
            {
                fullInstalled = true;
                fullPath = p;
                break;
            }
        }
#elif defined(PLATFORM_WINDOWS)
        if (!info.isSupercharged)
        {
            QDir winGetPackagesDir(localAppData + "/Microsoft/WinGet/Packages");
            if (winGetPackagesDir.exists())
            {
                QDirIterator it(winGetPackagesDir.absolutePath(), QStringList() << "ffmpeg.exe", QDir::Files, QDirIterator::Subdirectories);
                while (it.hasNext())
                {
                    QString candidate = it.next();
                    if (candidate.contains("full_build", Qt::CaseInsensitive) || candidate.contains("Gyan", Qt::CaseInsensitive))
                    {
                        fullInstalled = true;
                        fullPath = candidate;
                        break;
                    }
                }
            }
        }
#endif

        // 3. Determine status badge and action
        QString verDisplay = detectedVersion.isEmpty() ? "" : QString(" (v%1)").arg(detectedVersion);

#if defined(PLATFORM_DARWIN) || defined(__linux__)
        if (info.isSupercharged)
        {
            info.statusBadge = tr("Supercharged (Full Codecs)");
            info.details = tr("Active FFmpeg%1 build is FFmpeg-Full with extended codecs (H.265/HEVC, ProRes, AV1, extended filters).")
                               .arg(verDisplay);
            info.actionText = "";
        }
        else if (fullInstalled)
        {
            // Installed but shadowed by regular ffmpeg!
            info.isShadowed = true;
            info.statusBadge = tr("Shadowed by Standard FFmpeg");
            info.details =
                tr("Active FFmpeg%1 is standard FFmpeg. FFmpeg-Full is installed in %2 but shadowed in PATH.").arg(verDisplay, fullPath);
            info.actionText = tr("Relink FFmpeg-Full");
        }
        else
        {
            info.statusBadge = tr("Standard (Basic Codecs)");
            info.details = tr("Active FFmpeg%1 is standard FFmpeg. Full codec support (extended decoders & filters) requires FFmpeg-Full.")
                               .arg(verDisplay);
            info.actionText = tr("Install FFmpeg-Full (Homebrew)");
        }
#else
        // Windows
        if (info.isSupercharged)
        {
            info.statusBadge = tr("Supercharged (Full Codecs)");
            info.details =
                tr("Active FFmpeg%1 build is Gyan.dev Full Shared with extended codecs (H.265/HEVC, ProRes, AAC, extended filters).")
                    .arg(verDisplay);
            info.actionText = "";
        }
        else if (fullInstalled)
        {
            info.isShadowed = true;
            info.statusBadge = tr("Shadowed by Standard FFmpeg");
            info.details = tr("Active FFmpeg%1 is standard FFmpeg. FFmpeg Full Shared is installed at %2.").arg(verDisplay, fullPath);
            info.actionText = tr("Use Supercharged FFmpeg");
        }
        else
        {
            info.statusBadge = tr("Standard (Basic Codecs)");
            info.details =
                tr("Active FFmpeg%1 is standard OpenUTVDeps FFmpeg. Upgrade to FFmpeg Shared Full (v7.x–v9.x) via Gyan.dev or Winget.")
                    .arg(verDisplay);
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
            "C:/Program Files/Blackmagic Design/Blackmagic RAW",
            "C:/Program Files (x86)/Blackmagic Design/Blackmagic RAW",
            "C:/Program Files/Blackmagic Design/DaVinci Resolve",
            "C:/Program Files (x86)/Blackmagic Design/DaVinci Resolve",
            "C:/Program Files/Blackmagic Design/Blackmagic RAW/Blackmagic RAW SDK/Win/Libraries/BlackmagicRawAPI.dll",
            "C:/Program Files (x86)/Blackmagic Design/Blackmagic RAW/Blackmagic RAW SDK/Win/Libraries/BlackmagicRawAPI.dll",
            "C:/Program Files/Blackmagic Design/Blackmagic RAW/Blackmagic RAW Player/BlackmagicRawAPI/BlackmagicRawAPI.dll",
            "C:/Program Files (x86)/Blackmagic Design/Blackmagic RAW/Blackmagic RAW Player/BlackmagicRawAPI/BlackmagicRawAPI.dll"
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
            "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib", "/Library/NDI Tools for Apple/lib/macOS/libndi.dylib",
            "/usr/local/lib/libndi.dylib", "/opt/homebrew/lib/libndi.dylib"
#elif defined(PLATFORM_WINDOWS)
            "C:/Program Files/NDI/NDI 6 Tools/Runtime/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI 5 Tools/Runtime/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI Tools/Runtime/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI 6 Tools/Router/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI 5 Tools/Router/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI 6 Tools/Bridge/Processing.NDI.Lib.Advanced.x64.dll",
            "C:/Program Files/NDI/NDI 6 Tools/Discovery/Processing.NDI.Lib.Advanced.x64.dll",
            "C:/Program Files/NDI/NDI 6 Runtime/v6/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI 5 Runtime/v5/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI 6 SDK/Lib/x64/Processing.NDI.Lib.x64.dll",
            "C:/Program Files/NDI/NDI 5 SDK/Lib/x64/Processing.NDI.Lib.x64.dll",
            "C:/Program Files (x86)/NDI/NDI 6 Tools/Runtime/Processing.NDI.Lib.x64.dll",
            "C:/Program Files (x86)/NDI/NDI 5 Tools/Runtime/Processing.NDI.Lib.x64.dll"
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

#if defined(PLATFORM_WINDOWS)
        if (foundFile.isEmpty())
        {
            QStringList searchRoots = {"C:/Program Files/NDI", "C:/Program Files (x86)/NDI"};
            for (const auto& root : searchRoots)
            {
                if (QDir(root).exists())
                {
                    QDirIterator it(root, QStringList() << "Processing.NDI.Lib.x64.dll" << "Processing.NDI.Lib.Advanced.x64.dll",
                                    QDir::Files, QDirIterator::Subdirectories);
                    if (it.hasNext())
                    {
                        foundFile = it.next();
                        info.isAvailable = true;
                        break;
                    }
                }
            }
        }
#endif

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
