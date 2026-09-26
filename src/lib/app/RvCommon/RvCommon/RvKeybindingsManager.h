//
// Copyright (c) 2026 OpenUTV Contributors.
// All rights reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

#ifndef __RvCommon__RvKeybindingsManager__h__
#define __RvCommon__RvKeybindingsManager__h__

#include <QtCore/QString>
#include <QtCore/QJsonObject>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QObject>
#include <vector>

namespace Rv
{

    struct KeybindingItem
    {
        QString category;
        QString key;
        QString event;
        QString description;
    };

    struct RebindRule
    {
        QString mode;
        QString table;
        QString oldEvent;
        QString newEvent;
        QString description;
    };

    class RvKeybindingsManager : public QObject
    {
        Q_OBJECT

    public:
        static RvKeybindingsManager* instance();

        QString defaultKeybindingsPath() const;
        QString activeKeybindingsPath() const;

        bool ensureDefaultFileExists(const QString& path = QString());
        bool loadAndApply(const QString& path = QString());
        bool exportToFile(const QString& destPath) const;
        bool importFromFile(const QString& srcPath);

        const std::vector<KeybindingItem>& defaultShortcuts() const;
        const std::vector<RebindRule>& activeRebinds() const;

        static QString formatDisplayKey(const QString& rawKey);

    Q_SIGNALS:
        void keybindingsChanged();

    private:
        RvKeybindingsManager(QObject* parent = nullptr);
        virtual ~RvKeybindingsManager() = default;

        void initDefaultShortcuts();

        QString m_activePath;
        std::vector<KeybindingItem> m_defaultShortcuts;
        std::vector<RebindRule> m_activeRebinds;
    };

} // namespace Rv

#endif // __RvCommon__RvKeybindingsManager__h__
