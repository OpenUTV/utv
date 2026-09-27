//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#ifndef __RvCommon__RvCodecManager__h__
#define __RvCommon__RvCodecManager__h__

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <vector>

namespace Rv
{

    struct ThirdPartyCodecInfo
    {
        QString id;              // "ffmpeg", "braw", "red", "ndi", "videotoolbox"
        QString name;            // "FFmpeg Multimedia Engine", "Blackmagic RAW (BRAW)", etc.
        bool isAvailable;        // Is the engine/SDK installed & loadable?
        bool isSupercharged;     // For FFmpeg: has libx265/hevc/prores/aac?
        bool isShadowed;         // For macOS: ffmpeg-full is installed but regular ffmpeg is linked
        QString statusBadge;     // "Supercharged (Full Codecs)", "Standard (Basic Codecs)", "Available", "Not Installed"
        QString details;         // Path or version description
        QString actionText;      // Button text, e.g. "Relink FFmpeg-Full", "Supercharge FFmpeg...", "Get BRAW...", etc.
        QString helpUrl;         // Documentation or download link
        QString localFolderPath; // If applicable (e.g. RED SDK drop-in folder)
    };

    class RvCodecManager : public QObject
    {
        Q_OBJECT

    public:
        static RvCodecManager* instance();

        void probeAll();

        const std::vector<ThirdPartyCodecInfo>& codecs() const;
        const ThirdPartyCodecInfo* getCodec(const QString& id) const;

        bool isFFmpegSupercharged() const;
        bool isFFmpegShadowed() const;

        // Actions
        bool relinkFFmpegFull(QString& outMessage);
        void openRedFolder();
        QString getRedFolderPath() const;

    Q_SIGNALS:
        void statusUpdated();

    private:
        RvCodecManager(QObject* parent = nullptr);
        virtual ~RvCodecManager() = default;

        void probeFFmpeg();
        void probeBRAW();
        void probeRED();
        void probeNDI();
        void probeAppleCodecs();

        std::vector<ThirdPartyCodecInfo> m_codecs;
    };

} // namespace Rv

#endif // __RvCommon__RvCodecManager__h__
