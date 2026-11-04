//
//  Copyright (C) 2026  Contributors to the OpenUTV Project
//
//  SPDX-License-Identifier: Apache-2.0
//
#ifndef __TwkQtChat__Auth__h__
#define __TwkQtChat__Auth__h__
#include <QtCore/QByteArray>
#include <QtCore/QString>
#include <QtNetwork/QHostAddress>

namespace TwkQtChat
{
    //
    //  Authentication for network connections.
    //
    //  Same machine: each user has a random key in a private file. Both ends
    //  of a loopback connection prove they can read it with an HMAC over the
    //  connection's two ports, so another user on the machine can neither
    //  connect as this user nor relay a proof from one connection to another.
    //
    //  Other machines: "Always Allow" gives the peer a random pairing key, and
    //  the contact is trusted again only when its greeting proves it has the
    //  key. A user name and host name alone are never enough.
    //
    //  The file layout is shared with the Python clients in rvNetwork.py.
    //
    namespace Auth
    {
        //  Per-user directory for the keys, created with owner-only access.
        //  Empty if it can't be created.
        QString keyDirectory();

        //  Per-user directory for the files that tell rvpush which port each
        //  running UTV listens on. Empty if no safe directory is available.
        QString portFileDirectory();

        //  The user's local key, created on first use. Empty if unavailable.
        QByteArray localKey();

        //  Proof for a loopback connection. "fromServer" is true when the
        //  listening end makes the proof.
        QString makeLocalProof(bool fromServer, quint16 serverPort, quint16 clientPort);
        bool checkLocalProof(const QString& proof, bool fromServer, quint16 serverPort, quint16 clientPort);

        //  Pairing for remote contacts. The approving end creates and keeps
        //  a key per contact ("name@host"); the approved end keeps the keys
        //  it was given per peer address.
        QByteArray createPairingKey(const QString& contact);
        void forgetPairingKey(const QString& contact);
        bool checkPairingProof(const QString& contact, const QString& proof);

        void storeGivenPairingKey(const QHostAddress& peer, const QByteArray& key);
        QString makePairingProof(const QHostAddress& peer);

        //  Address in the form used for keys and comparisons (IPv4-mapped
        //  IPv6 addresses become IPv4).
        QHostAddress normalized(const QHostAddress& address);
    } // namespace Auth

} // namespace TwkQtChat

#endif // __TwkQtChat__Auth__h__
