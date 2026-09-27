//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#ifndef __RvCommon__RvCodecDialog__h__
#define __RvCommon__RvCodecDialog__h__

#include <QtWidgets/QDialog>
#include <QtWidgets/QLabel>
#include <QtWidgets/QPushButton>
#include <QtWidgets/QScrollArea>
#include <QtWidgets/QVBoxLayout>
#include <QtWidgets/QHBoxLayout>
#include <QtWidgets/QFrame>

namespace Rv
{

    class RvCodecDialog : public QDialog
    {
        Q_OBJECT

    public:
        explicit RvCodecDialog(QWidget* parent = nullptr);
        virtual ~RvCodecDialog() = default;

        void refreshUI();

    private Q_SLOTS:
        void onRelinkFFmpegClicked();
        void onInstallFFmpegHomebrewClicked();
        void onSuperchargeWindowsClicked();
        void onOpenRedFolderClicked();
        void onDownloadRedSdkClicked();
        void onGetBrawClicked();
        void onGetNdiClicked();
        void onRefreshClicked();

    private:
        void setupUI();
        QWidget* createCodecCard(const QString& id, const QString& title, const QString& badge, bool isOk, bool isWarning,
                                 const QString& desc, const QString& actionText, const char* actionSlot,
                                 const QString& secondActionText = QString(), const char* secondActionSlot = nullptr);

        QVBoxLayout* m_cardsLayout;
        QWidget* m_bannerWidget;
        QLabel* m_bannerLabel;
        QPushButton* m_bannerActionBtn;
    };

} // namespace Rv

#endif // __RvCommon__RvCodecDialog__h__
