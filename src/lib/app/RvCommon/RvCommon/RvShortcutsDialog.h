//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#ifndef __RvCommon__RvShortcutsDialog__h__
#define __RvCommon__RvShortcutsDialog__h__

#include <QtWidgets/QDialog>
#include <QtWidgets/QLineEdit>
#include <QtWidgets/QLabel>
#include <QtWidgets/QPushButton>
#include <QtWidgets/QScrollArea>
#include <QtWidgets/QVBoxLayout>
#include <QtWidgets/QHBoxLayout>
#include <QtWidgets/QGridLayout>
#include <vector>

namespace Rv
{

    class RvShortcutsDialog : public QDialog
    {
        Q_OBJECT

    public:
        explicit RvShortcutsDialog(QWidget* parent = nullptr);
        virtual ~RvShortcutsDialog() = default;

        void refreshShortcuts();

    protected:
        void keyPressEvent(QKeyEvent* event) override;
        void paintEvent(QPaintEvent* event) override;
        void showEvent(QShowEvent* event) override;
        void resizeEvent(QResizeEvent* event) override;

    private Q_SLOTS:
        void onSearchTextChanged(const QString& text);
        void onOpenKeybindingsFileClicked();
        void onImportClicked();
        void onExportClicked();
        void onReloadClicked();
        void onToggleWindowModeClicked();

    private:
        void setupUI();
        void buildCategorySections();
        void positionCenterOverParent();

        bool m_isStandaloneWindow;
        QLineEdit* m_searchEdit;
        QLabel* m_windowModeLabel;
        QLabel* m_filePathLabel;
        QWidget* m_cardsContainer;
        QScrollArea* m_scrollArea;

        struct ShortcutRowWidget
        {
            QWidget* container;
            QLabel* keyLabel;
            QLabel* descLabel;
            QString searchKeywords;
        };

        struct CategorySection
        {
            QString category;
            QWidget* groupWidget;
            QVBoxLayout* itemsLayout;
            std::vector<ShortcutRowWidget> rows;
        };

        std::vector<CategorySection> m_sections;
    };

} // namespace Rv

#endif // __RvCommon__RvShortcutsDialog__h__
