//
// Copyright (C) 2026  Contributors to the OpenUTV Project
//
// SPDX-License-Identifier: Apache-2.0
//
//  Checks how TwkQtChat decides whether a connection is trusted: the local
//  proof on loopback connections and pairing for connections from other
//  machines. Runs real servers and clients in one process, with the keys in a
//  temporary home directory.
//

#include <TwkQtChat/Auth.h>
#include <TwkQtChat/Client.h>
#include <TwkQtChat/Connection.h>

#include <QtCore/QCoreApplication>
#include <QtCore/QDir>
#include <QtCore/QElapsedTimer>
#include <QtCore/QFileInfo>
#include <QtCore/QMap>
#include <QtCore/QTemporaryDir>
#include <QtNetwork/QNetworkInterface>
#include <QtNetwork/QTcpSocket>

#include <functional>
#include <iostream>

using namespace std;
using namespace TwkQtChat;

namespace
{
    int failures = 0;

    void check(bool ok, const string& what)
    {
        cout << (ok ? "PASS: " : "FAIL: ") << what << endl;
        if (!ok)
            ++failures;
    }

    bool waitFor(const function<bool()>& done, int ms = 5000)
    {
        QElapsedTimer t;
        t.start();
        while (!done() && t.elapsed() < ms)
            QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        return done();
    }

    struct Seen
    {
        bool local = false;
        bool pairingCapable = false;
        bool paired = false;
        QString name;
    };

    //  What a Client's requestConnection handler saw, by remote name.
    struct Observer
    {
        QMap<QString, Seen> seen;
        bool giveKeys = false;

        void attach(Client* client)
        {
            QObject::connect(client, &Client::requestConnection,
                             [this](Connection* c)
                             {
                                 Seen s;
                                 s.name = c->remoteName();
                                 s.local = c->isLocal();
                                 s.pairingCapable = c->peerSupportsPairing();
                                 s.paired = Auth::checkPairingProof(c->remoteContactName(), c->pairingProof());
                                 if (giveKeys && !s.local && !s.paired && s.pairingCapable)
                                     c->sendPairingKey(Auth::createPairingKey(c->remoteContactName()));
                                 seen[s.name] = s;
                             });
        }
    };

    QByteArray greeting(const QByteArray& type, const QByteArray& payload)
    {
        return type + " " + QByteArray::number(payload.size()) + " " + payload;
    }

    //  Connect a raw socket, send one greeting, and wait until the server has
    //  seen it.
    Seen rawGreeting(Observer& server, quint16 port, const function<QByteArray(QTcpSocket&)>& makeGreeting, const QString& name)
    {
        QTcpSocket socket;
        socket.connectToHost(QHostAddress::LocalHost, port);
        if (!socket.waitForConnected(3000))
            return Seen();

        socket.write(makeGreeting(socket));
        socket.flush();
        //  A greeting the server never read would also look "not local".
        check(waitFor([&] { return server.seen.contains(name); }), "server read the greeting from " + name.toStdString());
        socket.abort();
        return server.seen.value(name);
    }

    QHostAddress lanAddress()
    {
        for (const QNetworkInterface& iface : QNetworkInterface::allInterfaces())
        {
            const auto flags = iface.flags();
            if (!(flags & QNetworkInterface::IsUp) || !(flags & QNetworkInterface::IsRunning) || (flags & QNetworkInterface::IsLoopBack))
                continue;

            for (const QNetworkAddressEntry& e : iface.addressEntries())
            {
                if (e.ip().protocol() == QAbstractSocket::IPv4Protocol && !e.ip().isLoopback() && !e.ip().isLinkLocal())
                    return e.ip();
            }
        }
        return QHostAddress();
    }
} // namespace

int main(int argc, char* argv[])
{
    //  Keep the keys out of the real home directory.
    QTemporaryDir home;
    qputenv("HOME", home.path().toUtf8());
    qputenv("XDG_DATA_HOME", (home.path() + "/data").toUtf8());
    qputenv("APPDATA", QDir::toNativeSeparators(home.path() + "/appdata").toUtf8());

    QCoreApplication app(argc, argv);

    check(Auth::keyDirectory().startsWith(home.path()), "keys live under the temporary home");
    check(Auth::localKey().size() == 32, "local key is created");
    check(Auth::localKey() == Auth::localKey(), "local key is stable");

#ifndef _WIN32
    const QFileInfo keyFile(Auth::keyDirectory() + "/local.key");
    check((keyFile.permissions() & (QFile::ReadGroup | QFile::ReadOther | QFile::WriteGroup | QFile::WriteOther)) == 0,
          "local key is readable only by its owner");

    const QFileInfo portDir(Auth::portFileDirectory());
    check(portDir.isDir() && (portDir.permissions() & (QFile::ReadGroup | QFile::ReadOther | QFile::WriteGroup | QFile::WriteOther)) == 0,
          "port file directory is private");
#endif

    //  Proofs are bound to the role and both ports.
    {
        const QString p = Auth::makeLocalProof(false, 4000, 5000);
        check(Auth::checkLocalProof(p, false, 4000, 5000), "local proof checks");
        check(!Auth::checkLocalProof(p, false, 4000, 5000), "local proof can't be used twice");
        check(!Auth::checkLocalProof(Auth::makeLocalProof(false, 4000, 5000), false, 4001, 5000),
              "local proof for another server port fails");
        check(!Auth::checkLocalProof(Auth::makeLocalProof(false, 4000, 5000), false, 4000, 5001),
              "local proof for another client port fails");
        check(!Auth::checkLocalProof(Auth::makeLocalProof(true, 4000, 5000), false, 4000, 5000),
              "server proof can't pass as a client proof");
    }

    Client server("server-user", "rv", 45300, false);
    check(server.online(), "server listens");
    const quint16 port = server.serverPort();
    Observer serverSaw;
    serverSaw.attach(&server);

    //  An OpenUTV client of the same user on this machine.
    {
        Client client("Same User", "rv", 0, false);
        Observer clientSaw;
        clientSaw.attach(&client);
        client.connectTo("server-user", QHostAddress::LocalHost, port);

        waitFor([&] { return serverSaw.seen.contains("Same User") && clientSaw.seen.contains("server-user"); });
        check(serverSaw.seen.value("Same User").local, "same-user client on loopback is local");
        check(serverSaw.seen.value("Same User").name == "Same User", "name with a space arrives intact");
        check(clientSaw.seen.value("server-user").local, "same-user server on loopback is local to the client");
    }

    //  Clients that don't prove anything.
    {
        Seen s = rawGreeting(serverSaw, port, [](QTcpSocket&) { return greeting("NEWGREETING", "old-tool rvController"); }, "old-tool");
        check(!s.local, "loopback client without a proof is not local");
        check(!s.pairingCapable, "old client isn't offered pairing");

        s = rawGreeting(serverSaw, port, [](QTcpSocket&) { return greeting("GREETING", "old rv"); }, "old rv");
        check(!s.local && s.name == "old rv", "old GREETING is read as before and is not local");

        s = rawGreeting(
            serverSaw, port, [](QTcpSocket&)
            { return greeting("NEWGREETING", "forger rvController utv=1;local=1700000000:00112233445566778899aabbccddeeff:00"); },
            "forger");
        check(!s.local, "forged proof is not local");

        s = rawGreeting(
            serverSaw, port,
            [port](QTcpSocket& sock)
            {
                //  A valid proof, but made for a different connection.
                const QString p = Auth::makeLocalProof(false, port, sock.localPort() + 1);
                return greeting("NEWGREETING", "relay rvController utv=1;local=" + p.toLatin1());
            },
            "relay");
        check(!s.local, "proof made for another connection is not local");

        s = rawGreeting(
            serverSaw, port,
            [port](QTcpSocket& sock)
            {
                const QString p = Auth::makeLocalProof(false, port, sock.localPort());
                return greeting("NEWGREETING", "python-tool rvController utv=1;local=" + p.toLatin1());
            },
            "python-tool");
        check(s.local, "tool that reads the key and proves it is local");
    }

    //  Pairing, over an address that isn't loopback.
    const QHostAddress lan = lanAddress();
    if (lan.isNull())
    {
        cout << "SKIP: no non-loopback IPv4 address for the pairing checks" << endl;
    }
    else
    {
        serverSaw.giveKeys = true;

        for (int round = 0; round < 2; ++round)
        {
            serverSaw.seen.remove("remote-user");
            Client client("remote-user", "rv", 0, false);
            client.connectTo("server-user", lan, port);
            waitFor([&] { return serverSaw.seen.contains("remote-user"); });

            const Seen s = serverSaw.seen.value("remote-user");
            check(!s.local, "connection over " + lan.toString().toStdString() + " is not local (round " + to_string(round + 1) + ")");
            check(s.pairingCapable, "OpenUTV peer can pair (round " + to_string(round + 1) + ")");

            if (round == 0)
            {
                check(!s.paired, "first connection isn't paired");
                //  Give the pairing key time to arrive.
                waitFor([&] { return !Auth::makePairingProof(lan).isEmpty(); });
                check(!Auth::makePairingProof(lan).isEmpty(), "peer stored the pairing key");
            }
            else
            {
                check(s.paired, "second connection proves the pairing");
            }
        }

        //  The same name from a peer without the key isn't paired.
        const QString contact = serverSaw.seen.value("remote-user").name;
        check(!Auth::checkPairingProof("remote-user@nowhere", Auth::makePairingProof(lan)),
              "pairing proof doesn't work for another contact");
    }

    cout << (failures ? "FAILED" : "ALL PASSED") << " (" << failures << " failures)" << endl;
    return failures ? 1 : 0;
}
