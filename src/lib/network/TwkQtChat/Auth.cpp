//
//  Copyright (C) 2026  Contributors to the OpenUTV Project
//
//  SPDX-License-Identifier: Apache-2.0
//
#include <TwkQtChat/Auth.h>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QHash>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QMessageAuthenticationCode>
#include <QtCore/QMutex>
#include <QtCore/QRandomGenerator>
#include <QtCore/QSaveFile>
#include <QtCore/QStringList>
#include <QtCore/QThread>
#include <iostream>

#ifndef _WIN32
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace TwkQtChat
{
    namespace Auth
    {
        using namespace std;

        namespace
        {
            const int KeyBytes = 32;
            const int NonceBytes = 16;
            const qint64 LocalWindowSecs = 120;
            const qint64 PairingWindowSecs = 600;
            const int MaxGivenKeysPerPeer = 8;

            const QFileDevice::Permissions OwnerOnlyFile = QFileDevice::ReadOwner | QFileDevice::WriteOwner;

            QMutex& storeMutex()
            {
                static QMutex m;
                return m;
            }

            QByteArray randomBytes(int n)
            {
                //  n is a multiple of 4.
                QByteArray b(n, Qt::Uninitialized);
                QRandomGenerator::system()->fillRange(reinterpret_cast<quint32*>(b.data()), n / 4);
                return b;
            }

            bool constantTimeEqual(const QByteArray& a, const QByteArray& b)
            {
                if (a.size() != b.size())
                    return false;

                unsigned char diff = 0;
                for (int i = 0; i < a.size(); ++i)
                    diff |= static_cast<unsigned char>(a[i] ^ b[i]);
                return diff == 0;
            }

            QByteArray hmacHex(const QByteArray& key, const QByteArray& message)
            {
                return QMessageAuthenticationCode::hash(message, key, QCryptographicHash::Sha256).toHex();
            }

            QString baseDirectory()
            {
#if defined(_WIN32)
                const QString appData = qEnvironmentVariable("APPDATA");
                if (appData.isEmpty())
                    return QString();
                return QDir::fromNativeSeparators(appData) + "/OpenUTV/network";
#elif defined(__APPLE__)
                return QDir::homePath() + "/Library/Application Support/OpenUTV/network";
#else
                QString data = qEnvironmentVariable("XDG_DATA_HOME");
                if (data.isEmpty())
                    data = QDir::homePath() + "/.local/share";
                return data + "/openutv/network";
#endif
            }

#ifndef _WIN32
            //  The directory must be a real directory owned by this user. Fix
            //  its mode if it's open to others.
            bool ownedPrivateDirectory(const QString& path)
            {
                const QByteArray p = QFile::encodeName(path);
                struct stat st;

                if (lstat(p.constData(), &st) != 0 || !S_ISDIR(st.st_mode) || st.st_uid != getuid())
                    return false;

                if ((st.st_mode & 077) != 0 && chmod(p.constData(), 0700) != 0)
                    return false;

                return true;
            }
#endif

            //  Seconds since the epoch, and whether a proof's time is close
            //  enough to now.
            qint64 now() { return QDateTime::currentSecsSinceEpoch(); }

            //  Nonces of proofs already accepted, so a proof can't be used
            //  twice.
            bool isReplay(const QByteArray& nonce, qint64 window)
            {
                static QHash<QByteArray, qint64> seen;
                const qint64 t = now();

                for (auto i = seen.begin(); i != seen.end();)
                {
                    if (t - i.value() > 2 * window)
                        i = seen.erase(i);
                    else
                        ++i;
                }

                if (seen.contains(nonce))
                    return true;

                seen.insert(nonce, t);
                return false;
            }

            //  Split "time:nonce:mac" and check the time and the nonce's form.
            bool parseProof(const QString& proof, qint64 window, QByteArray& time, QByteArray& nonce, QByteArray& macs)
            {
                const QStringList parts = proof.split(':');
                if (parts.size() != 3)
                    return false;

                bool ok = false;
                const qint64 t = parts[0].toLongLong(&ok);
                if (!ok || qAbs(now() - t) > window)
                    return false;

                nonce = parts[1].toLatin1();
                if (nonce.size() != 2 * NonceBytes || QByteArray::fromHex(nonce).size() != NonceBytes)
                    return false;

                time = parts[0].toLatin1();
                macs = parts[2].toLatin1();
                return !macs.isEmpty();
            }

            QByteArray localMessage(bool fromServer, const QByteArray& time, const QByteArray& nonce, quint16 serverPort,
                                    quint16 clientPort)
            {
                return QByteArray("utv-local-v1|") + (fromServer ? "server" : "client") + "|" + time + "|" + nonce + "|"
                       + QByteArray::number(serverPort) + "|" + QByteArray::number(clientPort);
            }

            QByteArray pairingMessage(const QByteArray& time, const QByteArray& nonce)
            {
                return QByteArray("utv-pair-v1|") + time + "|" + nonce;
            }

            QString pairingPath()
            {
                const QString dir = keyDirectory();
                return dir.isEmpty() ? QString() : dir + "/pairing.json";
            }

            QJsonObject loadPairing()
            {
                QFile f(pairingPath());
                if (!f.open(QIODevice::ReadOnly))
                    return QJsonObject();
                return QJsonDocument::fromJson(f.readAll()).object();
            }

            void savePairing(const QJsonObject& store)
            {
                const QString path = pairingPath();
                if (path.isEmpty())
                    return;

                QSaveFile f(path);
                if (!f.open(QIODevice::WriteOnly))
                {
                    cerr << "ERROR: cannot write " << path.toStdString() << endl;
                    return;
                }
                f.setPermissions(OwnerOnlyFile);
                f.write(QJsonDocument(store).toJson());
                if (!f.commit())
                    cerr << "ERROR: cannot write " << path.toStdString() << endl;
                QFile::setPermissions(path, OwnerOnlyFile);
            }
        } // namespace

        QHostAddress normalized(const QHostAddress& address)
        {
            bool ok = false;
            const quint32 v4 = address.toIPv4Address(&ok);
            return ok ? QHostAddress(v4) : address;
        }

        QString keyDirectory()
        {
            const QString dir = baseDirectory();
            if (dir.isEmpty() || !QDir().mkpath(dir))
                return QString();
#ifndef _WIN32
            if (!ownedPrivateDirectory(dir))
            {
                cerr << "ERROR: " << dir.toStdString() << " is not a private directory owned by this user" << endl;
                return QString();
            }
#endif
            return dir;
        }

        QString portFileDirectory()
        {
#ifdef _WIN32
            //  The temp directory is already per user.
            const QString dir = QDir::tempPath() + "/openutv-network";
            return QDir().mkpath(dir) ? dir : QString();
#else
            //  /tmp is shared, so another user could create the directory
            //  first. Create it ourselves with mode 0700, or accept it only if
            //  it's a directory we own.
            const QString dir = QDir::tempPath() + QString("/openutv-network-%1").arg(getuid());
            const QByteArray p = QFile::encodeName(dir);

            if (mkdir(p.constData(), 0700) != 0 && errno != EEXIST)
                return QString();

            if (!ownedPrivateDirectory(dir))
            {
                cerr << "ERROR: " << dir.toStdString() << " is not a private directory owned by this user" << endl;
                return QString();
            }
            return dir;
#endif
        }

        QByteArray localKey()
        {
            const QString dir = keyDirectory();
            if (dir.isEmpty())
                return QByteArray();

            const QString path = dir + "/local.key";

            for (int attempt = 0; attempt < 20; ++attempt)
            {
                QFile f(path);

                if (f.open(QIODevice::ReadOnly))
                {
                    const QByteArray hex = f.readAll().trimmed();
                    f.close();
                    const QByteArray key = QByteArray::fromHex(hex);

                    if (hex.size() == 2 * KeyBytes && key.size() == KeyBytes)
                    {
#ifndef _WIN32
                        const QFileDevice::Permissions others =
                            QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ReadOther | QFileDevice::WriteOther;
                        if (QFileInfo(path).permissions() & others)
                            QFile::setPermissions(path, OwnerOnlyFile);
#endif
                        return key;
                    }

                    //  Another process may still be writing it. If it stays
                    //  unreadable, replace it.
                    if (attempt < 10)
                    {
                        QThread::msleep(20);
                        continue;
                    }
                    QFile::remove(path);
                }

                QFile created(path);
                if (created.open(QIODevice::WriteOnly | QIODevice::NewOnly))
                {
                    created.setPermissions(OwnerOnlyFile);
                    const QByteArray key = randomBytes(KeyBytes);
                    created.write(key.toHex() + "\n");
                    created.close();
                    return key;
                }

                //  Another process created it first. Read that one.
                QThread::msleep(20);
            }

            cerr << "ERROR: cannot read or create " << path.toStdString() << endl;
            return QByteArray();
        }

        QString makeLocalProof(bool fromServer, quint16 serverPort, quint16 clientPort)
        {
            const QByteArray key = localKey();
            if (key.isEmpty())
                return QString();

            const QByteArray time = QByteArray::number(now());
            const QByteArray nonce = randomBytes(NonceBytes).toHex();
            const QByteArray mac = hmacHex(key, localMessage(fromServer, time, nonce, serverPort, clientPort));
            return QString::fromLatin1(time + ":" + nonce + ":" + mac);
        }

        bool checkLocalProof(const QString& proof, bool fromServer, quint16 serverPort, quint16 clientPort)
        {
            QByteArray time, nonce, mac;
            if (!parseProof(proof, LocalWindowSecs, time, nonce, mac))
                return false;

            const QByteArray key = localKey();
            if (key.isEmpty())
                return false;

            const QByteArray expected = hmacHex(key, localMessage(fromServer, time, nonce, serverPort, clientPort));
            if (!constantTimeEqual(mac, expected))
                return false;

            QMutexLocker lock(&storeMutex());
            return !isReplay(nonce, LocalWindowSecs);
        }

        QByteArray createPairingKey(const QString& contact)
        {
            QMutexLocker lock(&storeMutex());
            const QByteArray key = randomBytes(KeyBytes);

            QJsonObject store = loadPairing();
            QJsonObject trusted = store["trusted"].toObject();
            trusted[contact] = QString::fromLatin1(key.toHex());
            store["trusted"] = trusted;
            savePairing(store);

            return key;
        }

        void forgetPairingKey(const QString& contact)
        {
            QMutexLocker lock(&storeMutex());
            QJsonObject store = loadPairing();
            QJsonObject trusted = store["trusted"].toObject();
            if (!trusted.contains(contact))
                return;
            trusted.remove(contact);
            store["trusted"] = trusted;
            savePairing(store);
        }

        bool checkPairingProof(const QString& contact, const QString& proof)
        {
            QByteArray time, nonce, macs;
            if (!parseProof(proof, PairingWindowSecs, time, nonce, macs))
                return false;

            QMutexLocker lock(&storeMutex());
            const QByteArray key = QByteArray::fromHex(loadPairing()["trusted"].toObject()[contact].toString().toLatin1());
            if (key.size() != KeyBytes)
                return false;

            const QByteArray expected = hmacHex(key, pairingMessage(time, nonce));
            bool match = false;
            for (const QByteArray& mac : macs.split(','))
                match = constantTimeEqual(mac, expected) || match;

            return match && !isReplay(nonce, PairingWindowSecs);
        }

        void storeGivenPairingKey(const QHostAddress& peer, const QByteArray& key)
        {
            if (key.size() != KeyBytes)
                return;

            QMutexLocker lock(&storeMutex());
            const QString address = normalized(peer).toString();
            const QString hex = QString::fromLatin1(key.toHex());

            QJsonObject store = loadPairing();
            QJsonObject given = store["given"].toObject();
            QJsonArray keys = given[address].toArray();

            for (int i = keys.size() - 1; i >= 0; --i)
            {
                if (keys[i].toString() == hex)
                    keys.removeAt(i);
            }
            keys.append(hex);
            while (keys.size() > MaxGivenKeysPerPeer)
                keys.removeFirst();

            given[address] = keys;
            store["given"] = given;
            savePairing(store);
        }

        QString makePairingProof(const QHostAddress& peer)
        {
            QMutexLocker lock(&storeMutex());
            const QJsonArray keys = loadPairing()["given"].toObject()[normalized(peer).toString()].toArray();
            if (keys.isEmpty())
                return QString();

            const QByteArray time = QByteArray::number(now());
            const QByteArray nonce = randomBytes(NonceBytes).toHex();
            const QByteArray message = pairingMessage(time, nonce);

            QList<QByteArray> macs;
            for (const QJsonValue& v : keys)
            {
                const QByteArray key = QByteArray::fromHex(v.toString().toLatin1());
                if (key.size() == KeyBytes)
                    macs.append(hmacHex(key, message));
            }

            if (macs.isEmpty())
                return QString();

            return QString::fromLatin1(time + ":" + nonce + ":" + macs.join(','));
        }

    } // namespace Auth
} // namespace TwkQtChat
