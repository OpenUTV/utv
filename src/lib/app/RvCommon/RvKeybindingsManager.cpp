//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#include <RvCommon/RvKeybindingsManager.h>
#include <RvApp/RvSession.h>
#include <TwkApp/Document.h>
#include <TwkApp/Mode.h>
#include <TwkApp/EventTable.h>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QStandardPaths>
#include <QtCore/QTextStream>
#include <QtCore/QDebug>

#include <cstdlib>

namespace Rv
{

    RvKeybindingsManager* RvKeybindingsManager::instance()
    {
        static RvKeybindingsManager s_instance;
        return &s_instance;
    }

    RvKeybindingsManager::RvKeybindingsManager(QObject* parent)
        : QObject(parent)
    {
        initDefaultShortcuts();
    }

    QString RvKeybindingsManager::defaultKeybindingsPath() const
    {
        // 1. Environment variable override
        const char* envPath = getenv("OPENUTV_KEYBINDINGS_FILE");
        if (!envPath)
        {
            envPath = getenv("RV_KEYBINDINGS_FILE");
        }
        if (envPath && strlen(envPath) > 0)
        {
            return QString::fromUtf8(envPath);
        }

        // 2. Standard AppData / AppConfig location
        QString baseDir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
        if (baseDir.isEmpty())
        {
            baseDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        }
        if (baseDir.isEmpty())
        {
            baseDir = QDir::homePath() + "/.openutv";
        }

        QDir dir(baseDir);
        if (!dir.exists())
        {
            dir.mkpath(".");
        }

        return dir.filePath("keybindings.json");
    }

    QString RvKeybindingsManager::activeKeybindingsPath() const
    {
        if (!m_activePath.isEmpty())
        {
            return m_activePath;
        }
        return defaultKeybindingsPath();
    }

    void RvKeybindingsManager::initDefaultShortcuts()
    {
        m_defaultShortcuts = {// Playback & Navigation
                              {"Playback & Navigation", "Space", "key-down--space", "Toggle Playback"},
                              {"Playback & Navigation", "Right", "key-down--right", "Step Forward 1 Frame"},
                              {"Playback & Navigation", "Left", "key-down--left", "Step Backward 1 Frame"},
                              {"Playback & Navigation", "Shift + Right", "key-down--shift--right", "Step Forward 10 Frames"},
                              {"Playback & Navigation", "Shift + Left", "key-down--shift--left", "Step Backward 10 Frames"},
                              {"Playback & Navigation", "Home", "key-down--home", "Jump to Beginning of Range"},
                              {"Playback & Navigation", "End", "key-down--end", "Jump to End of Range"},
                              {"Playback & Navigation", "Up", "key-down--up", "Toggle Forward / Backward Playback"},
                              {"Playback & Navigation", "Down", "key-down--down", "Toggle Play"},
                              {"Playback & Navigation", "Enter", "key-down--enter", "Set Frame Number Direct Input"},
                              {"Playback & Navigation", "P", "key-down--p", "Toggle Premult Display"},

                              // Viewing & Display
                              {"Viewing & Display", "F", "key-down--f", "Frame Image in View"},
#if defined(PLATFORM_DARWIN)
                              {"Viewing & Display", "⌘ + F", "key-down--control--f", "Frame Image Width"},
#else
                              {"Viewing & Display", "Ctrl + F", "key-down--control--f", "Frame Image Width"},
#endif
                              {"Viewing & Display", "` (or ~)", "key-down--~", "Toggle Fullscreen Mode"},
                              {"Viewing & Display", "W", "key-down--w", "Fit Window to Image"},
                              {"Viewing & Display", "Shift + W", "key-down--W", "Center Fit (1:1 Pixels)"},
                              {"Viewing & Display", "1", "key-down--1", "Scale 100% (1:1)"},
                              {"Viewing & Display", "T / Tab", "key-down--t", "Toggle Heads-Up Timeline"},
                              {"Viewing & Display", "F1", "key-down--f1", "Toggle Menu Bar Visibility"},
                              {"Viewing & Display", "F2", "key-down--f2", "Toggle Timeline Visibility"},
                              {"Viewing & Display", "F3", "key-down--f3", "Toggle Timeline Magnifier"},
                              {"Viewing & Display", "F4 / I", "key-down--f4", "Toggle Heads-Up Image Info"},
                              {"Viewing & Display", "F5", "key-down--f5", "Toggle Heads-Up Color Inspector"},
                              {"Viewing & Display", "F6", "key-down--f6", "Toggle Wipes"},
                              {"Viewing & Display", "F7", "key-down--f7", "Toggle Heads-Up Info Strip"},
                              {"Viewing & Display", "F8", "key-down--f8", "Toggle External Process Progress"},
                              {"Viewing & Display", "F11", "key-down--f11", "Toggle Heads-Up Source Details"},
                              {"Viewing & Display", "N", "key-down--n", "Toggle Nearest / Linear Filter"},

                              // Color & Channels
                              {"Color & Channels", "C", "key-down--c", "Show All Channels (RGB)"},
                              {"Color & Channels", "R", "key-down--r", "Show Red Channel"},
                              {"Color & Channels", "G", "key-down--g", "Show Green Channel"},
                              {"Color & Channels", "B", "key-down--b", "Show Blue Channel"},
                              {"Color & Channels", "A", "key-down--a", "Show Alpha Channel"},
                              {"Color & Channels", "L", "key-down--l", "Show Luminance Channel"},
                              {"Color & Channels", "V", "key-down--v", "Enter Display Gamma"},
                              {"Color & Channels", "E", "key-down--e", "Edit Current Source Exposure"},
                              {"Color & Channels", "Y", "key-down--y", "Edit Current Source Gamma"},
                              {"Color & Channels", "K", "key-down--k", "Edit Current Source Contrast"},
                              {"Color & Channels", "H", "key-down--h", "Edit Current Source Hue"},
                              {"Color & Channels", "Shift + S", "key-down--S", "Edit Current Source Saturation"},
                              {"Color & Channels", "Shift + B", "key-down--B", "Edit Display Brightness"},
                              {"Color & Channels", "Shift + D", "key-down--D", "Toggle Display LUT Active"},
                              {"Color & Channels", "Shift + Home", "key-down--shift--home", "Reset All Color Parameters"},

                              // Marking & In/Out
                              {"Marking & In/Out", "M", "key-down--m", "Toggle Mark at Current Frame"},
                              {"Marking & In/Out", "Page Down", "key-down--page-down", "Set In/Out to Previous Marked Range"},
                              {"Marking & In/Out", "Page Up", "key-down--page-up", "Set In/Out to Next Marked Range"},
                              {"Marking & In/Out", "|", "key-down--|", "Set In/Out Range From Surrounding Marks"},

        // Session & Tools
#if defined(PLATFORM_DARWIN)
                              {"Session & Tools", "⌘ + O", "key-down--control--o", "Open Media..."},
                              {"Session & Tools", "⌘ + Shift + O", "key-down--control--O", "Open in New Session..."},
                              {"Session & Tools", "⌘ + S", "key-down--control--s", "Save Session"},
                              {"Session & Tools", "⌘ + Shift + S", "key-down--control--S", "Save Session As..."},
                              {"Session & Tools", "⌘ + E", "key-down--control--e", "Export Quicktime Movie..."},
                              {"Session & Tools", "⌘ + N", "key-down--control--N", "Clear Session"},
                              {"Session & Tools", "⌘ + P", "key-down--control--p", "Toggle Presentation Mode"},
                              {"Session & Tools", "⌘ + I", "key-down--control--i", "Show Media Information Dialog"},
                              {"Session & Tools", "⌘ + Ctrl + ?", "key-down--control--meta--?", "Describe Key / Event Inspector"},
#else
                              {"Session & Tools", "Ctrl + O", "key-down--control--o", "Open Media..."},
                              {"Session & Tools", "Ctrl + Shift + O", "key-down--control--O", "Open in New Session..."},
                              {"Session & Tools", "Ctrl + S", "key-down--control--s", "Save Session"},
                              {"Session & Tools", "Ctrl + Shift + S", "key-down--control--S", "Save Session As..."},
                              {"Session & Tools", "Ctrl + E", "key-down--control--e", "Export Quicktime Movie..."},
                              {"Session & Tools", "Ctrl + N", "key-down--control--N", "Clear Session"},
                              {"Session & Tools", "Ctrl + P", "key-down--control--p", "Toggle Presentation Mode"},
                              {"Session & Tools", "Ctrl + I", "key-down--control--i", "Show Media Information Dialog"},
                              {"Session & Tools", "Ctrl + Alt + ?", "key-down--control--alt--?", "Describe Key / Event Inspector"},
#endif
                              {"Session & Tools", "?", "key-down--?", "Show Keyboard Shortcuts Overlay"},
                              {"Session & Tools", "Esc", "key-down--escape", "Close Overlay / Cancel"}};
    }

    const std::vector<KeybindingItem>& RvKeybindingsManager::defaultShortcuts() const { return m_defaultShortcuts; }

    const std::vector<RebindRule>& RvKeybindingsManager::activeRebinds() const { return m_activeRebinds; }

    bool RvKeybindingsManager::ensureDefaultFileExists(const QString& path)
    {
        QString filePath = path.isEmpty() ? defaultKeybindingsPath() : path;
        if (QFile::exists(filePath))
        {
            return true;
        }

        QFileInfo info(filePath);
        QDir dir = info.dir();
        if (!dir.exists())
        {
            dir.mkpath(".");
        }

        QJsonObject root;
        root["version"] = 1;
        root["appName"] = "OpenUTV";
        root["description"] = "OpenUTV Keyboard Shortcuts and Rebindings Configuration";
        root["instructions"] = "To customize a keybinding, add an entry to the 'rebinds' array below. "
                               "The 'mode' defaults to 'rvui', and 'table' defaults to 'global'. "
                               "Example: { \"mode\": \"rvui\", \"table\": \"global\", \"oldEvent\": \"key-down--space\", \"newEvent\": "
                               "\"key-down--k\", \"description\": \"Toggle Playback\" }. "
                               "This file is cross-platform and can be transferred between macOS, Windows, and Linux machines.";

        QJsonArray rebindsArr;
        root["rebinds"] = rebindsArr;

        QJsonArray defaultsArr;
        for (const auto& item : m_defaultShortcuts)
        {
            QJsonObject s;
            s["category"] = item.category;
            s["key"] = item.key;
            s["event"] = item.event;
            s["description"] = item.description;
            defaultsArr.append(s);
        }
        root["defaultShortcuts"] = defaultsArr;

        QJsonDocument doc(root);
        QFile file(filePath);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        {
            return false;
        }

        file.write(doc.toJson(QJsonDocument::Indented));
        file.close();
        m_activePath = filePath;
        return true;
    }

    bool RvKeybindingsManager::loadAndApply(const QString& path)
    {
        QString filePath = path.isEmpty() ? defaultKeybindingsPath() : path;
        if (!QFile::exists(filePath))
        {
            ensureDefaultFileExists(filePath);
            m_activePath = filePath;
            return true;
        }

        QFile file(filePath);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        {
            return false;
        }

        QByteArray data = file.readAll();
        file.close();

        QJsonParseError parseErr;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);
        if (parseErr.error != QJsonParseError::NoError || !doc.isObject())
        {
            return false;
        }

        QJsonObject root = doc.object();
        m_activeRebinds.clear();

        if (root.contains("rebinds") && root["rebinds"].isArray())
        {
            QJsonArray rebindsArr = root["rebinds"].toArray();
            for (const QJsonValue& val : rebindsArr)
            {
                if (val.isObject())
                {
                    QJsonObject obj = val.toObject();
                    RebindRule rule;
                    rule.mode = obj.value("mode").toString("rvui");
                    rule.table = obj.value("table").toString("global");
                    rule.oldEvent = obj.value("oldEvent").toString();
                    rule.newEvent = obj.value("newEvent").toString();
                    rule.description = obj.value("description").toString();

                    if (!rule.oldEvent.isEmpty() && !rule.newEvent.isEmpty())
                    {
                        m_activeRebinds.push_back(rule);
                    }
                }
            }
        }

        // Apply to open documents / sessions if available
        const auto& docs = TwkApp::Document::documents();
        if (!docs.empty())
        {
            for (TwkApp::Document* doc : docs)
            {
                int applied = 0;
                for (const auto& rule : m_activeRebinds)
                {
                    if (TwkApp::Mode* mode = doc->findModeByName(rule.mode.toUtf8().constData()))
                    {
                        if (TwkApp::EventTable* table = mode->findTableByName(rule.table.toUtf8().constData()))
                        {
                            table->rebind(rule.oldEvent.toUtf8().constData(), rule.newEvent.toUtf8().constData());
                            applied++;
                        }
                    }
                }
                if (applied > 0)
                {
                    doc->invalidateEventTables();
                }
            }
        }
        else if (RvSession* session = RvSession::currentRvSession())
        {
            int applied = 0;
            for (const auto& rule : m_activeRebinds)
            {
                if (TwkApp::Mode* mode = session->findModeByName(rule.mode.toUtf8().constData()))
                {
                    if (TwkApp::EventTable* table = mode->findTableByName(rule.table.toUtf8().constData()))
                    {
                        table->rebind(rule.oldEvent.toUtf8().constData(), rule.newEvent.toUtf8().constData());
                        applied++;
                    }
                }
            }
            if (applied > 0)
            {
                session->invalidateEventTables();
            }
        }

        m_activePath = filePath;
        Q_EMIT keybindingsChanged();
        return true;
    }

    bool RvKeybindingsManager::exportToFile(const QString& destPath) const
    {
        if (destPath.isEmpty())
        {
            return false;
        }

        QJsonObject root;
        root["version"] = 1;
        root["appName"] = "OpenUTV";
        root["description"] = "OpenUTV Keybindings Configuration";

        QJsonArray rebindsArr;
        for (const auto& rule : m_activeRebinds)
        {
            QJsonObject r;
            r["mode"] = rule.mode;
            r["table"] = rule.table;
            r["oldEvent"] = rule.oldEvent;
            r["newEvent"] = rule.newEvent;
            r["description"] = rule.description;
            rebindsArr.append(r);
        }
        root["rebinds"] = rebindsArr;

        QJsonArray defaultsArr;
        for (const auto& item : m_defaultShortcuts)
        {
            QJsonObject s;
            s["category"] = item.category;
            s["key"] = item.key;
            s["event"] = item.event;
            s["description"] = item.description;
            defaultsArr.append(s);
        }
        root["defaultShortcuts"] = defaultsArr;

        QJsonDocument doc(root);
        QFile file(destPath);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        {
            return false;
        }

        file.write(doc.toJson(QJsonDocument::Indented));
        file.close();
        return true;
    }

    bool RvKeybindingsManager::importFromFile(const QString& srcPath)
    {
        if (!QFile::exists(srcPath))
        {
            return false;
        }

        QString targetPath = defaultKeybindingsPath();
        if (QFile::exists(targetPath))
        {
            QFile::remove(targetPath);
        }

        if (!QFile::copy(srcPath, targetPath))
        {
            return false;
        }

        return loadAndApply(targetPath);
    }

    QString RvKeybindingsManager::formatDisplayKey(const QString& rawKey)
    {
        QString k = rawKey;
#if defined(PLATFORM_DARWIN)
        k.replace("Ctrl +", "⌘ +");
        k.replace("Control +", "⌘ +");
        k.replace("Alt +", "⌥ +");
        k.replace("Shift +", "⇧ +");
#endif
        return k;
    }

} // namespace Rv
