//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#include <RvCommon/RvShortcutsDialog.h>
#include <RvCommon/RvKeybindingsManager.h>

#include <QtWidgets/QApplication>
#include <QtWidgets/QFileDialog>
#include <QtWidgets/QMessageBox>
#include <QtWidgets/QFrame>
#include <QtWidgets/QSplitter>
#include <QtGui/QPainter>
#include <QtGui/QPainterPath>
#include <QtGui/QKeyEvent>
#include <QtGui/QDesktopServices>
#include <QtGui/QScreen>
#include <QtCore/QUrl>
#include <QtCore/QFileInfo>

namespace Rv
{

    RvShortcutsDialog::RvShortcutsDialog(QWidget* parent)
        : QDialog(parent)
        , m_isStandaloneWindow(false)
        , m_searchEdit(nullptr)
        , m_windowModeLabel(nullptr)
        , m_filePathLabel(nullptr)
        , m_cardsContainer(nullptr)
        , m_scrollArea(nullptr)
    {
        setWindowFlags(Qt::Dialog | Qt::FramelessWindowHint);
        setAttribute(Qt::WA_TranslucentBackground, true);
        setModal(false);

        resize(980, 680);
        setMinimumSize(780, 520);

        setupUI();
        refreshShortcuts();

        connect(RvKeybindingsManager::instance(), &RvKeybindingsManager::keybindingsChanged, this, &RvShortcutsDialog::refreshShortcuts);
    }

    void RvShortcutsDialog::setupUI()
    {
        QVBoxLayout* rootLayout = new QVBoxLayout(this);
        rootLayout->setContentsMargins(20, 18, 20, 18);
        rootLayout->setSpacing(14);

        // 1. Header Bar
        QHBoxLayout* headerLayout = new QHBoxLayout();
        headerLayout->setContentsMargins(4, 0, 4, 0);

        QLabel* titleLabel = new QLabel(tr("Keyboard shortcuts"), this);
        titleLabel->setStyleSheet("font-size: 19px; font-weight: 700; color: #ffffff; letter-spacing: 0.5px;");

        m_windowModeLabel = new QLabel(tr("Open in a new window"), this);
        m_windowModeLabel->setCursor(Qt::PointingHandCursor);
        m_windowModeLabel->setStyleSheet("color: #f1c40f; font-size: 13px; font-weight: 600; text-decoration: none;");

        QLabel* pipeLabel = new QLabel("|", this);
        pipeLabel->setStyleSheet("color: #7f8c8d; font-size: 13px; margin: 0 4px;");

        QLabel* closeLink = new QLabel(tr("Close"), this);
        closeLink->setCursor(Qt::PointingHandCursor);
        closeLink->setStyleSheet("color: #f1c40f; font-size: 13px; font-weight: 600;");

        QPushButton* closeBtn = new QPushButton("✕", this);
        closeBtn->setCursor(Qt::PointingHandCursor);
        closeBtn->setFixedSize(26, 26);
        closeBtn->setStyleSheet("QPushButton { background: transparent; color: #cccccc; font-size: 15px; font-weight: bold; border: none; "
                                "border-radius: 13px; } "
                                "QPushButton:hover { background: rgba(255, 255, 255, 0.15); color: #ffffff; }");

        connect(closeBtn, &QPushButton::clicked, this, &QDialog::accept);

        headerLayout->addWidget(titleLabel);
        headerLayout->addStretch(1);
        headerLayout->addWidget(m_windowModeLabel);
        headerLayout->addWidget(pipeLabel);
        headerLayout->addWidget(closeLink);
        headerLayout->addSpacing(8);
        headerLayout->addWidget(closeBtn);

        rootLayout->addLayout(headerLayout);

        // Make windowModeLabel and closeLink clickable
        m_windowModeLabel->installEventFilter(this);
        closeLink->installEventFilter(this);

        // 2. Search Box
        QHBoxLayout* searchLayout = new QHBoxLayout();
        m_searchEdit = new QLineEdit(this);
        m_searchEdit->setPlaceholderText(tr("Search shortcuts (e.g. space, frame, color, ⌘)..."));
        m_searchEdit->setClearButtonEnabled(true);
        m_searchEdit->setStyleSheet("QLineEdit { background-color: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.18); "
                                    "border-radius: 8px; padding: 7px 14px; color: #ffffff; font-size: 13px; selection-background-color: "
                                    "#f1c40f; selection-color: #111111; } "
                                    "QLineEdit:focus { border: 1px solid #f1c40f; background-color: rgba(255, 255, 255, 0.12); }");

        connect(m_searchEdit, &QLineEdit::textChanged, this, &RvShortcutsDialog::onSearchTextChanged);
        searchLayout->addWidget(m_searchEdit);
        rootLayout->addLayout(searchLayout);

        // 3. Scrollable Shortcuts Grid
        m_scrollArea = new QScrollArea(this);
        m_scrollArea->setWidgetResizable(true);
        m_scrollArea->setFrameShape(QFrame::NoFrame);
        m_scrollArea->setStyleSheet(
            "QScrollArea { background: transparent; border: none; } "
            "QScrollBar:vertical { background: rgba(0, 0, 0, 0.2); width: 8px; border-radius: 4px; } "
            "QScrollBar::handle:vertical { background: rgba(255, 255, 255, 0.25); min-height: 20px; border-radius: 4px; } "
            "QScrollBar::handle:vertical:hover { background: #f1c40f; } "
            "QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0px; }");

        m_cardsContainer = new QWidget();
        m_cardsContainer->setStyleSheet("background: transparent;");
        m_scrollArea->setWidget(m_cardsContainer);

        rootLayout->addWidget(m_scrollArea, 1);

        // 4. Footer Bar
        QFrame* separator = new QFrame(this);
        separator->setFrameShape(QFrame::HLine);
        separator->setFrameShadow(QFrame::Plain);
        separator->setStyleSheet("color: rgba(255, 255, 255, 0.12); height: 1px;");
        rootLayout->addWidget(separator);

        QHBoxLayout* footerLayout = new QHBoxLayout();
        footerLayout->setContentsMargins(4, 2, 4, 2);

        QPushButton* openFileBtn = new QPushButton(tr("Open Keybindings File"), this);
        QPushButton* importBtn = new QPushButton(tr("Import..."), this);
        QPushButton* exportBtn = new QPushButton(tr("Export..."), this);
        QPushButton* reloadBtn = new QPushButton(tr("Reload"), this);

        QString actionBtnStyle =
            "QPushButton { background-color: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.18); "
            "border-radius: 6px; padding: 6px 14px; color: #e0e0e0; font-size: 12px; font-weight: 600; } "
            "QPushButton:hover { background-color: rgba(255, 255, 255, 0.16); color: #ffffff; border-color: #f1c40f; } "
            "QPushButton:pressed { background-color: rgba(241, 196, 15, 0.25); color: #f1c40f; }";

        openFileBtn->setStyleSheet(actionBtnStyle);
        importBtn->setStyleSheet(actionBtnStyle);
        exportBtn->setStyleSheet(actionBtnStyle);
        reloadBtn->setStyleSheet(actionBtnStyle);

        openFileBtn->setCursor(Qt::PointingHandCursor);
        importBtn->setCursor(Qt::PointingHandCursor);
        exportBtn->setCursor(Qt::PointingHandCursor);
        reloadBtn->setCursor(Qt::PointingHandCursor);

        connect(openFileBtn, &QPushButton::clicked, this, &RvShortcutsDialog::onOpenKeybindingsFileClicked);
        connect(importBtn, &QPushButton::clicked, this, &RvShortcutsDialog::onImportClicked);
        connect(exportBtn, &QPushButton::clicked, this, &RvShortcutsDialog::onExportClicked);
        connect(reloadBtn, &QPushButton::clicked, this, &RvShortcutsDialog::onReloadClicked);

        footerLayout->addWidget(openFileBtn);
        footerLayout->addWidget(importBtn);
        footerLayout->addWidget(exportBtn);
        footerLayout->addWidget(reloadBtn);
        footerLayout->addStretch(1);

        m_filePathLabel = new QLabel(this);
        m_filePathLabel->setStyleSheet("color: #888888; font-size: 11px;");
        footerLayout->addWidget(m_filePathLabel);
        footerLayout->addSpacing(12);

        QPushButton* doneBtn = new QPushButton(tr("Close (Esc)"), this);
        doneBtn->setCursor(Qt::PointingHandCursor);
        doneBtn->setStyleSheet("QPushButton { background-color: #f1c40f; border: none; border-radius: 6px; "
                               "padding: 6px 18px; color: #1e1e24; font-size: 12px; font-weight: 700; } "
                               "QPushButton:hover { background-color: #ffd54f; } "
                               "QPushButton:pressed { background-color: #d4ac0d; }");
        connect(doneBtn, &QPushButton::clicked, this, &QDialog::accept);
        footerLayout->addWidget(doneBtn);

        rootLayout->addLayout(footerLayout);
    }

    void RvShortcutsDialog::refreshShortcuts()
    {
        buildCategorySections();

        QString activePath = RvKeybindingsManager::instance()->activeKeybindingsPath();
        QFileInfo fi(activePath);
        m_filePathLabel->setText(tr("File: %1").arg(fi.fileName()));
        m_filePathLabel->setToolTip(activePath);
    }

    void RvShortcutsDialog::buildCategorySections()
    {
        // Clear previous widgets
        qDeleteAll(m_cardsContainer->children());
        m_sections.clear();

        const auto& allItems = RvKeybindingsManager::instance()->defaultShortcuts();
        const auto& rebinds = RvKeybindingsManager::instance()->activeRebinds();

        // Group items by category preserving insertion order
        std::vector<QString> categories;
        for (const auto& item : allItems)
        {
            if (std::find(categories.begin(), categories.end(), item.category) == categories.end())
            {
                categories.push_back(item.category);
            }
        }

        // 3-column layout inside cards container
        QHBoxLayout* columnsLayout = new QHBoxLayout(m_cardsContainer);
        columnsLayout->setContentsMargins(6, 6, 6, 6);
        columnsLayout->setSpacing(24);

        // We distribute categories across 3 columns
        // Column 0: Playback & Navigation, Marking & In/Out
        // Column 1: Viewing & Display
        // Column 2: Color & Channels, Session & Tools
        std::vector<QVBoxLayout*> colLayouts(3);
        for (int c = 0; c < 3; ++c)
        {
            QWidget* colWidget = new QWidget(m_cardsContainer);
            colWidget->setStyleSheet("background: transparent;");
            QVBoxLayout* v = new QVBoxLayout(colWidget);
            v->setContentsMargins(0, 0, 0, 0);
            v->setSpacing(22);
            columnsLayout->addWidget(colWidget, 1);
            colLayouts[c] = v;
        }

        for (const auto& cat : categories)
        {
            int targetCol = 0;
            if (cat == "Viewing & Display")
            {
                targetCol = 1;
            }
            else if (cat == "Color & Channels" || cat == "Session & Tools")
            {
                targetCol = 2;
            }

            QWidget* groupWidget = new QWidget(m_cardsContainer);
            groupWidget->setStyleSheet("background: transparent;");
            QVBoxLayout* groupLayout = new QVBoxLayout(groupWidget);
            groupLayout->setContentsMargins(0, 0, 0, 0);
            groupLayout->setSpacing(7);

            QLabel* catHeader = new QLabel(cat, groupWidget);
            catHeader->setStyleSheet("color: #f1c40f; font-size: 14px; font-weight: 700; padding-bottom: 2px;");
            groupLayout->addWidget(catHeader);

            CategorySection section;
            section.category = cat;
            section.groupWidget = groupWidget;
            section.itemsLayout = groupLayout;

            for (const auto& item : allItems)
            {
                if (item.category != cat)
                {
                    continue;
                }

                // Check if there is an active custom rebind for this item's event
                QString displayKey = item.key;
                for (const auto& r : rebinds)
                {
                    if (r.oldEvent == item.event && !r.newEvent.isEmpty())
                    {
                        displayKey = QString("%1 (Custom)").arg(r.newEvent);
                        break;
                    }
                }

                QWidget* rowWidget = new QWidget(groupWidget);
                rowWidget->setStyleSheet("background: transparent;");
                QHBoxLayout* rowLayout = new QHBoxLayout(rowWidget);
                rowLayout->setContentsMargins(0, 1, 0, 1);
                rowLayout->setSpacing(6);

                QLabel* keyLabel = new QLabel(displayKey, rowWidget);
                keyLabel->setStyleSheet("color: #ffd54f; font-size: 13px; font-weight: 700; font-family: -apple-system, "
                                        "BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;");
                keyLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
                keyLabel->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Preferred);

                QLabel* colonLabel = new QLabel(":", rowWidget);
                colonLabel->setStyleSheet("color: #f1c40f; font-size: 13px; font-weight: 700;");

                QLabel* descLabel = new QLabel(item.description, rowWidget);
                descLabel->setStyleSheet("color: #f2f2f2; font-size: 13px; font-weight: 400;");
                descLabel->setWordWrap(true);

                rowLayout->addWidget(keyLabel);
                rowLayout->addWidget(colonLabel);
                rowLayout->addWidget(descLabel, 1);

                groupLayout->addWidget(rowWidget);

                ShortcutRowWidget rw;
                rw.container = rowWidget;
                rw.keyLabel = keyLabel;
                rw.descLabel = descLabel;
                rw.searchKeywords = (cat + " " + displayKey + " " + item.description + " " + item.event).toLower();
                section.rows.push_back(rw);
            }

            colLayouts[targetCol]->addWidget(groupWidget);
            m_sections.push_back(section);
        }

        // Add stretches to each column to keep items neatly packed at the top
        for (int c = 0; c < 3; ++c)
        {
            colLayouts[c]->addStretch(1);
        }
    }

    void RvShortcutsDialog::onSearchTextChanged(const QString& query)
    {
        QString needle = query.trimmed().toLower();

        for (auto& sec : m_sections)
        {
            int visibleCount = 0;
            for (auto& row : sec.rows)
            {
                bool match = needle.isEmpty() || row.searchKeywords.contains(needle);
                row.container->setVisible(match);
                if (match)
                {
                    visibleCount++;
                }
            }
            sec.groupWidget->setVisible(visibleCount > 0);
        }
    }

    void RvShortcutsDialog::onOpenKeybindingsFileClicked()
    {
        QString filePath = RvKeybindingsManager::instance()->activeKeybindingsPath();
        RvKeybindingsManager::instance()->ensureDefaultFileExists(filePath);
        QDesktopServices::openUrl(QUrl::fromLocalFile(filePath));
    }

    void RvShortcutsDialog::onImportClicked()
    {
        QString filename = QFileDialog::getOpenFileName(this, tr("Import Keybindings Configuration"), QDir::homePath(),
                                                        tr("JSON Files (*.json);;All Files (*)"));

        if (!filename.isEmpty())
        {
            if (RvKeybindingsManager::instance()->importFromFile(filename))
            {
                refreshShortcuts();
                QMessageBox::information(this, tr("Import Successful"), tr("Keybindings imported successfully and applied."));
            }
            else
            {
                QMessageBox::warning(this, tr("Import Failed"), tr("Could not import keybindings from the selected file."));
            }
        }
    }

    void RvShortcutsDialog::onExportClicked()
    {
        QString filename = QFileDialog::getSaveFileName(this, tr("Export Keybindings Configuration"),
                                                        QDir::homePath() + "/keybindings.json", tr("JSON Files (*.json);;All Files (*)"));

        if (!filename.isEmpty())
        {
            if (RvKeybindingsManager::instance()->exportToFile(filename))
            {
                QMessageBox::information(this, tr("Export Successful"), tr("Keybindings exported successfully to:\n%1").arg(filename));
            }
            else
            {
                QMessageBox::warning(this, tr("Export Failed"), tr("Could not export keybindings to the selected file."));
            }
        }
    }

    void RvShortcutsDialog::onReloadClicked()
    {
        RvKeybindingsManager::instance()->loadAndApply();
        refreshShortcuts();
    }

    void RvShortcutsDialog::onToggleWindowModeClicked()
    {
        m_isStandaloneWindow = !m_isStandaloneWindow;
        bool wasVisible = isVisible();
        hide();

        if (m_isStandaloneWindow)
        {
            setWindowFlags(Qt::Window | Qt::WindowTitleHint | Qt::WindowSystemMenuHint | Qt::WindowMinMaxButtonsHint
                           | Qt::WindowCloseButtonHint);
            setAttribute(Qt::WA_TranslucentBackground, false);
            m_windowModeLabel->setText(tr("Dock as overlay"));
            setWindowTitle(tr("OpenUTV Keyboard Shortcuts"));
            setStyleSheet("QDialog { background-color: #1e1e24; color: #ffffff; }");
        }
        else
        {
            setWindowFlags(Qt::Dialog | Qt::FramelessWindowHint);
            setAttribute(Qt::WA_TranslucentBackground, true);
            m_windowModeLabel->setText(tr("Open in a new window"));
            setStyleSheet("");
        }

        if (wasVisible)
        {
            show();
            raise();
            activateWindow();
        }
    }

    void RvShortcutsDialog::positionCenterOverParent()
    {
        QWidget* p = parentWidget();
        if (p)
        {
            QRect pGeom = p->geometry();
            int cx = pGeom.left() + (pGeom.width() - width()) / 2;
            int cy = pGeom.top() + (pGeom.height() - height()) / 2;

            QScreen* screen = p->screen();
            if (screen)
            {
                QRect scr = screen->availableGeometry();
                cx = std::max(scr.left() + 20, std::min(cx, scr.right() - width() - 20));
                cy = std::max(scr.top() + 20, std::min(cy, scr.bottom() - height() - 20));
            }
            move(cx, cy);
        }
    }

    void RvShortcutsDialog::showEvent(QShowEvent* event)
    {
        QDialog::showEvent(event);
        if (!m_isStandaloneWindow)
        {
            positionCenterOverParent();
        }
        if (m_searchEdit)
        {
            m_searchEdit->setFocus();
            m_searchEdit->selectAll();
        }
    }

    void RvShortcutsDialog::resizeEvent(QResizeEvent* event) { QDialog::resizeEvent(event); }

    void RvShortcutsDialog::paintEvent(QPaintEvent* event)
    {
        if (!m_isStandaloneWindow)
        {
            QPainter p(this);
            p.setRenderHint(QPainter::Antialiasing);

            QRectF r = rect();
            r.adjust(0.5, 0.5, -0.5, -0.5);

            QPainterPath path;
            path.addRoundedRect(r, 14, 14);

            // Dark translucent charcoal background matching Gmail shortcut modal
            p.fillPath(path, QColor(24, 24, 28, 244));

            // Subtle elegant border
            p.setPen(QPen(QColor(255, 255, 255, 36), 1.0));
            p.drawPath(path);
        }
        else
        {
            QDialog::paintEvent(event);
        }
    }

    void RvShortcutsDialog::keyPressEvent(QKeyEvent* event)
    {
        if (event->key() == Qt::Key_Escape)
        {
            accept();
            return;
        }

        if (event->key() == Qt::Key_Question && !m_searchEdit->hasFocus())
        {
            accept();
            return;
        }

        // Handle clicking labels via enter or space if focused
        QDialog::keyPressEvent(event);
    }

    bool RvShortcutsDialog::eventFilter(QObject* obj, QEvent* event)
    {
        if (event->type() == QEvent::MouseButtonRelease)
        {
            if (obj == m_windowModeLabel)
            {
                onToggleWindowModeClicked();
                return true;
            }
            else if (obj->inherits("QLabel") && static_cast<QLabel*>(obj)->text() == tr("Close"))
            {
                accept();
                return true;
            }
        }
        return QDialog::eventFilter(obj, event);
    }

} // namespace Rv
