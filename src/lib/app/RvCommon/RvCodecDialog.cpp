//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#include <RvCommon/RvCodecDialog.h>
#include <RvCommon/RvCodecManager.h>

#include <QtWidgets/QMessageBox>
#include <QtWidgets/QApplication>
#include <QtWidgets/QScrollArea>
#include <QtGui/QDesktopServices>
#include <QtGui/QClipboard>
#include <QtGui/QGuiApplication>
#include <QtCore/QUrl>

namespace Rv
{

    RvCodecDialog::RvCodecDialog(QWidget* parent)
        : QDialog(parent)
        , m_cardsLayout(nullptr)
        , m_bannerWidget(nullptr)
        , m_bannerLabel(nullptr)
        , m_bannerActionBtn(nullptr)
    {
        setWindowTitle(tr("Codecs & Professional SDKs Status"));
        resize(760, 620);
        setMinimumSize(640, 480);

        setupUI();
        refreshUI();

        connect(RvCodecManager::instance(), &RvCodecManager::statusUpdated, this, &RvCodecDialog::refreshUI);
    }

    void RvCodecDialog::setupUI()
    {
        QVBoxLayout* rootLayout = new QVBoxLayout(this);
        rootLayout->setContentsMargins(18, 16, 18, 16);
        rootLayout->setSpacing(14);

        // 1. Header
        QHBoxLayout* headerLayout = new QHBoxLayout();
        QLabel* titleLabel = new QLabel(tr("Media Codecs & Third-Party SDKs"), this);
        titleLabel->setStyleSheet("font-size: 18px; font-weight: 700; color: #ffffff;");
        headerLayout->addWidget(titleLabel);
        headerLayout->addStretch(1);
        rootLayout->addLayout(headerLayout);

        // 2. Banner area (alerts when FFmpeg-full is shadowed or actions needed)
        m_bannerWidget = new QWidget(this);
        QHBoxLayout* bannerLayout = new QHBoxLayout(m_bannerWidget);
        bannerLayout->setContentsMargins(12, 10, 12, 10);
        m_bannerLabel = new QLabel(m_bannerWidget);
        m_bannerLabel->setWordWrap(true);
        m_bannerActionBtn = new QPushButton(m_bannerWidget);
        m_bannerActionBtn->setCursor(Qt::PointingHandCursor);

        bannerLayout->addWidget(m_bannerLabel, 1);
        bannerLayout->addWidget(m_bannerActionBtn);
        rootLayout->addWidget(m_bannerWidget);

        // 3. Scrollable Cards Container
        QScrollArea* scrollArea = new QScrollArea(this);
        scrollArea->setWidgetResizable(true);
        scrollArea->setFrameShape(QFrame::NoFrame);

        QWidget* cardsContainer = new QWidget();
        cardsContainer->setStyleSheet("background: transparent;");
        m_cardsLayout = new QVBoxLayout(cardsContainer);
        m_cardsLayout->setContentsMargins(0, 0, 0, 0);
        m_cardsLayout->setSpacing(12);

        scrollArea->setWidget(cardsContainer);
        rootLayout->addWidget(scrollArea, 1);

        // 4. Footer Bar
        QFrame* sep = new QFrame(this);
        sep->setFrameShape(QFrame::HLine);
        sep->setStyleSheet("color: rgba(255, 255, 255, 0.12);");
        rootLayout->addWidget(sep);

        QHBoxLayout* footerLayout = new QHBoxLayout();
        QPushButton* refreshBtn = new QPushButton(tr("Refresh"), this);
        refreshBtn->setStyleSheet("QPushButton { background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.18); "
                                  "border-radius: 6px; padding: 6px 14px; color: #ffffff; font-weight: 600; } "
                                  "QPushButton:hover { background: rgba(255, 255, 255, 0.15); border-color: #f1c40f; }");
        refreshBtn->setCursor(Qt::PointingHandCursor);
        connect(refreshBtn, &QPushButton::clicked, this, &RvCodecDialog::onRefreshClicked);

        QPushButton* closeBtn = new QPushButton(tr("Close"), this);
        closeBtn->setStyleSheet("QPushButton { background: #f1c40f; border: none; border-radius: 6px; "
                                "padding: 6px 18px; color: #1e1e24; font-weight: 700; } "
                                "QPushButton:hover { background: #ffd54f; }");
        closeBtn->setCursor(Qt::PointingHandCursor);
        connect(closeBtn, &QPushButton::clicked, this, &QDialog::accept);

        footerLayout->addWidget(refreshBtn);
        footerLayout->addStretch(1);
        footerLayout->addWidget(closeBtn);
        rootLayout->addLayout(footerLayout);
    }

    QWidget* RvCodecDialog::createCodecCard(const QString& id, const QString& title, const QString& badge, bool isOk, bool isWarning,
                                            const QString& desc, const QString& actionText, const char* actionSlot,
                                            const QString& secondActionText, const char* secondActionSlot)
    {
        QWidget* card = new QWidget();
        card->setStyleSheet("QWidget { background-color: rgba(255, 255, 255, 0.04); border: 1px solid rgba(255, 255, 255, 0.12); "
                            "border-radius: 8px; }");

        QVBoxLayout* cardLayout = new QVBoxLayout(card);
        cardLayout->setContentsMargins(14, 12, 14, 12);
        cardLayout->setSpacing(8);

        QHBoxLayout* topRow = new QHBoxLayout();
        QLabel* nameLabel = new QLabel(title, card);
        nameLabel->setStyleSheet("font-size: 15px; font-weight: 700; color: #ffffff; border: none; background: transparent;");

        QLabel* badgeLabel = new QLabel(badge, card);
        QString badgeStyle = "font-size: 11px; font-weight: 700; padding: 3px 8px; border-radius: 4px; border: none; ";
        if (isOk)
        {
            badgeStyle += "background-color: rgba(46, 204, 113, 0.2); color: #2ecc71; border: 1px solid #2ecc71;";
        }
        else if (isWarning)
        {
            badgeStyle += "background-color: rgba(241, 196, 15, 0.2); color: #f1c40f; border: 1px solid #f1c40f;";
        }
        else
        {
            badgeStyle += "background-color: rgba(189, 195, 199, 0.15); color: #bdc3c7; border: 1px solid #7f8c8d;";
        }
        badgeLabel->setStyleSheet(badgeStyle);

        topRow->addWidget(nameLabel);
        topRow->addSpacing(8);
        topRow->addWidget(badgeLabel);
        topRow->addStretch(1);
        cardLayout->addLayout(topRow);

        QLabel* descLabel = new QLabel(desc, card);
        descLabel->setStyleSheet("color: #cccccc; font-size: 12px; border: none; background: transparent;");
        descLabel->setWordWrap(true);
        cardLayout->addWidget(descLabel);

        if (!actionText.isEmpty() || !secondActionText.isEmpty())
        {
            QHBoxLayout* btnRow = new QHBoxLayout();
            btnRow->addStretch(1);

            if (!secondActionText.isEmpty())
            {
                QPushButton* btn2 = new QPushButton(secondActionText, card);
                btn2->setStyleSheet("QPushButton { background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.18); "
                                    "border-radius: 5px; padding: 5px 12px; color: #e0e0e0; font-size: 12px; font-weight: 600; } "
                                    "QPushButton:hover { background: rgba(255, 255, 255, 0.16); color: #ffffff; border-color: #f1c40f; }");
                btn2->setCursor(Qt::PointingHandCursor);
                if (secondActionSlot)
                {
                    connect(btn2, SIGNAL(clicked()), this, secondActionSlot);
                }
                btnRow->addWidget(btn2);
                btnRow->addSpacing(6);
            }

            if (!actionText.isEmpty())
            {
                QPushButton* btn = new QPushButton(actionText, card);
                QString primaryBtnStyle = "QPushButton { background: #f1c40f; border: none; border-radius: 5px; "
                                          "padding: 5px 14px; color: #1e1e24; font-size: 12px; font-weight: 700; } "
                                          "QPushButton:hover { background: #ffd54f; }";
                btn->setStyleSheet(primaryBtnStyle);
                btn->setCursor(Qt::PointingHandCursor);
                if (actionSlot)
                {
                    connect(btn, SIGNAL(clicked()), this, actionSlot);
                }
                btnRow->addWidget(btn);
            }

            cardLayout->addLayout(btnRow);
        }

        return card;
    }

    void RvCodecDialog::refreshUI()
    {
        // Clear existing cards
        qDeleteAll(m_cardsLayout->parentWidget()->findChildren<QWidget*>(QString(), Qt::FindDirectChildrenOnly));

        RvCodecManager::instance()->probeAll();
        const auto& codecs = RvCodecManager::instance()->codecs();

        bool isShadowed = RvCodecManager::instance()->isFFmpegShadowed();

        if (isShadowed)
        {
            m_bannerWidget->setStyleSheet("background-color: rgba(241, 196, 15, 0.15); border: 1px solid #f1c40f; border-radius: 6px;");
            m_bannerLabel->setStyleSheet("color: #f1c40f; font-weight: 600; font-size: 13px;");
            m_bannerLabel->setText(tr("⚠️ Action Recommended: FFmpeg-Full is installed on your system but shadowed by standard FFmpeg. "
                                      "Click 'Relink FFmpeg-Full' to restore H.265/HEVC, AAC, and extended codecs."));
            m_bannerActionBtn->setText(tr("Relink FFmpeg-Full"));
            m_bannerActionBtn->setStyleSheet(
                "QPushButton { background: #f1c40f; color: #1e1e24; font-weight: bold; border-radius: 4px; padding: 6px 14px; } "
                "QPushButton:hover { background: #ffd54f; }");
            m_bannerActionBtn->disconnect();
            connect(m_bannerActionBtn, &QPushButton::clicked, this, &RvCodecDialog::onRelinkFFmpegClicked);
            m_bannerWidget->setVisible(true);
        }
        else
        {
            m_bannerWidget->setVisible(false);
        }

        for (const auto& c : codecs)
        {
            bool isOk = c.isSupercharged || (c.isAvailable && !c.isShadowed);
            bool isWarning = c.isShadowed || (!c.isSupercharged && c.id == "ffmpeg");

            const char* slot = nullptr;
            const char* slot2 = nullptr;
            QString action2;

            if (c.id == "ffmpeg")
            {
                if (c.isShadowed)
                {
                    slot = SLOT(onRelinkFFmpegClicked());
                }
                else if (!c.isSupercharged)
                {
#if defined(PLATFORM_DARWIN) || defined(__linux__)
                    slot = SLOT(onRelinkFFmpegClicked());
#else
                    slot = SLOT(onSuperchargeWindowsClicked());
#endif
                }
            }
            else if (c.id == "braw")
            {
                if (!c.isAvailable)
                {
                    slot = SLOT(onGetBrawClicked());
                }
            }
            else if (c.id == "red")
            {
                if (c.isAvailable)
                {
                    slot = SLOT(onOpenRedFolderClicked());
                }
                else
                {
                    slot = SLOT(onDownloadRedSdkClicked());
                    action2 = tr("Open RED Folder");
                    slot2 = SLOT(onOpenRedFolderClicked());
                }
            }
            else if (c.id == "ndi")
            {
                if (!c.isAvailable)
                {
                    slot = SLOT(onGetNdiClicked());
                }
            }

            QWidget* card = createCodecCard(c.id, c.name, c.statusBadge, isOk, isWarning, c.details, c.actionText, slot, action2, slot2);
            m_cardsLayout->addWidget(card);
        }

        m_cardsLayout->addStretch(1);
    }

    void RvCodecDialog::onRelinkFFmpegClicked()
    {
        QString msg;
        bool ok = RvCodecManager::instance()->relinkFFmpegFull(msg);
        if (ok)
        {
            QMessageBox::information(this, tr("FFmpeg Relink"), msg);
            refreshUI();
        }
        else
        {
            // Provide copyable command
            QString cmd = "brew unlink ffmpeg-full && brew unlink ffmpeg && brew link --overwrite ffmpeg-full";
            QGuiApplication::clipboard()->setText(cmd);
            QMessageBox::warning(this, tr("FFmpeg Relink"), tr("%1\n\nThe command has been copied to your clipboard:\n%2").arg(msg, cmd));
        }
    }

    void RvCodecDialog::onSuperchargeWindowsClicked()
    {
        QString info = tr("To enable H.265/HEVC, ProRes, and AAC on Windows, install FFmpeg Shared builds:\n\n"
                          "Option 1 (Winget):\n"
                          "  winget install \"FFmpeg (Shared)\"\n\n"
                          "Option 2 (Scoop):\n"
                          "  scoop install ffmpeg-shared\n\n"
                          "Option 3 (Manual Download):\n"
                          "  Download 'ffmpeg-release-full-shared.7z' from https://www.gyan.dev/ffmpeg/builds/\n\n"
                          "Click 'Copy Winget Command' to copy the command to your clipboard.");

        QMessageBox msgBox(this);
        msgBox.setWindowTitle(tr("Supercharge FFmpeg on Windows"));
        msgBox.setText(info);
        QPushButton* copyBtn = msgBox.addButton(tr("Copy Winget Command"), QMessageBox::ActionRole);
        QPushButton* gyanBtn = msgBox.addButton(tr("Open Gyan.dev"), QMessageBox::ActionRole);
        msgBox.addButton(QMessageBox::Close);

        msgBox.exec();

        if (msgBox.clickedButton() == copyBtn)
        {
            QGuiApplication::clipboard()->setText("winget install \"FFmpeg (Shared)\"");
            QMessageBox::information(this, tr("Copied"), tr("Winget install command copied to clipboard."));
        }
        else if (msgBox.clickedButton() == gyanBtn)
        {
            QDesktopServices::openUrl(QUrl("https://www.gyan.dev/ffmpeg/builds/"));
        }
    }

    void RvCodecDialog::onOpenRedFolderClicked() { RvCodecManager::instance()->openRedFolder(); }

    void RvCodecDialog::onDownloadRedSdkClicked() { QDesktopServices::openUrl(QUrl("https://www.red.com/download/r3d-sdk")); }

    void RvCodecDialog::onGetBrawClicked()
    {
        QDesktopServices::openUrl(QUrl("https://www.blackmagicdesign.com/support/family/professional-cameras"));
    }

    void RvCodecDialog::onGetNdiClicked() { QDesktopServices::openUrl(QUrl("https://ndi.video/tools/")); }

    void RvCodecDialog::onRefreshClicked() { refreshUI(); }

} // namespace Rv
