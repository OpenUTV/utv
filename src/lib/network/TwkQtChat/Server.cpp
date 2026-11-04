//
//  Copyright (c) 2008 Tweak Software.
//  All rights reserved.
//
//  SPDX-License-Identifier: Apache-2.0
//
//
#include <TwkQtChat/Server.h>
#include <TwkQtChat/Connection.h>
#include <QtNetwork/QtNetwork>
#include <QtNetwork/QTcpSocket>
#include <iostream>

namespace TwkQtChat
{
    using namespace std;

    Server::Server(QObject* parent, int port, ConnectionFactory fact)
        : QTcpServer(parent)
        , m_connectionFactory(fact)
    {
        int fallbackCount = 10;
        if (getenv("TWK_SERVER_PORT_FALLBACK_COUNT"))
        {
            fallbackCount = atoi(getenv("TWK_SERVER_PORT_FALLBACK_COUNT"));
        }

        // Disable application-wide proxy if any for this QTcpServer
        setProxy(QNetworkProxy::NoProxy);

        //
        //  Listen on the first port in the range that we can bind. Binding is
        //  the reliable test: connecting to a port to see whether something
        //  answers can report a connection where there is none.
        //

        for (int p = port; p <= port + fallbackCount; ++p)
        {
            if (listen(QHostAddress::Any, p))
                return;
        }

        cerr << "ERROR: RvNetwork: cannot listen on any network port, tried " << port << "-" << port + fallbackCount << " - "
             << errorString().toStdString() << endl;
    }

    void Server::incomingConnection(qintptr socketDescriptor)
    {
        Connection* connection = 0;
        if (m_connectionFactory)
            connection = (*m_connectionFactory)(this, true);
        else
            connection = new Connection(this, true);

        connection->setSocketDescriptor(socketDescriptor);
        emit newConnection(connection);
    }

} // namespace TwkQtChat
