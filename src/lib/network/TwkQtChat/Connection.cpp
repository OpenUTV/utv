//
//  Copyright (c) 2008 Tweak Software.
//  All rights reserved.
//
//  SPDX-License-Identifier: Apache-2.0
//
//
#include <iostream>
#include <TwkQtChat/Connection.h>
#include <TwkQtChat/Auth.h>
#include <QtNetwork/QtNetwork>

#if 0
#define DB_ICON 0x01
#define DB_ALL 0xff

//  #define DB_LEVEL        (DB_ALL & (~ DB_ICON))
#define DB_LEVEL DB_ALL

#define DB(x) cerr << "Connection: " << x << endl
#define DBL(level, x)     \
    if (level & DB_LEVEL) \
    cerr << "Connection: " << x << endl
#else
#define DB(x)
#define DBL(level, x)
#endif

namespace TwkQtChat
{
    using namespace std;

    static int TransferTimeout = 60 * 1000 * 10;
    static int PongTimeout = 60 * 1000 * 10;
    static int PingInterval = 15 * 1000;
    static const char SeparatorToken = ' ';

    Connection::Connection(QObject* parent, bool pingpong)
        : QTcpSocket(parent)
    {
        m_greetingName = tr("undefined");
        m_greetingApp = tr("undefined");
        m_expectedContactName = tr("");
        m_remoteContactName = tr("unknown");
        m_state = WaitingForGreeting;
        m_currentDataType = Undefined;
        m_numBytesForCurrentDataType = -1;
        m_transferTimerId = 0;
        m_isGreetingMessageSent = false;
        m_local = false;
        m_pingpong = pingpong;
        m_duplicate = false;
        m_incoming = true;
        m_peerSupportsPairing = false;

        static bool first = true;

        if (first)
        {
            bool print = false;

            if (getenv("RV_CONNECTION_PONG_TIMEOUT"))
            {
                int i = atoi(getenv("RV_CONNECTION_PONG_TIMEOUT"));
                if (i <= 0)
                    m_pingpong = false;
                else
                    PongTimeout = 1000 * i;
                print = true;
            }
            if (getenv("RV_CONNECTION_PING_INTERVAL"))
            {
                int i = atoi(getenv("RV_CONNECTION_PING_INTERVAL"));
                if (i <= 0)
                    m_pingpong = false;
                else
                    PingInterval = 1000 * i;
                print = true;
            }
            if (getenv("RV_CONNECTION_TRANSFERTIMEOUT"))
            {
                int i = atoi(getenv("RV_CONNECTION_TRANSFERTIMEOUT"));
                if (i > 0)
                    TransferTimeout = 1000 * i;
                print = true;
            }

            if (print)
                cerr << "INFO: Connection timing: pingpong " << m_pingpong << " pongtimeout " << PongTimeout << " pinginterval "
                     << PingInterval << " transtimeout " << TransferTimeout << endl;

            first = false;
        }

        m_pingTimer.setInterval(PingInterval);

        QObject::connect(this, SIGNAL(readyRead()), this, SLOT(processReadyRead()));
        QObject::connect(this, SIGNAL(disconnected()), &m_pingTimer, SLOT(stop()));
        QObject::connect(&m_pingTimer, SIGNAL(timeout()), this, SLOT(sendPing()));
        QObject::connect(this, SIGNAL(connected()), this, SLOT(sendGreetingMessage()));
    }

    Connection::~Connection() {}

    void Connection::connectToContact(const QString& name, const QHostAddress& ip, quint16 port, OpenMode openMode)
    {
        m_expectedContactName = name;
        m_expectedAddress = ip;
        m_incoming = false;
        connectToHost(ip, port, openMode);
    }

    const QHostAddress& Connection::expectedAddress() const { return m_expectedAddress; }

    const QString& Connection::expectedContactName() const { return m_expectedContactName; }

    const QString& Connection::remoteName() const { return m_remoteName; }

    const QString& Connection::remoteApp() const { return m_remoteApp; }

    const QString& Connection::remoteContactName() const { return m_remoteContactName; }

    void Connection::setGreetingMessage(const QString& message, const QString& app)
    {
        m_greetingName = message;
        m_greetingApp = app;
    }

    bool Connection::sendMessage(const QString& message)
    {
        DB("sendMessage " << message.toUtf8().data());
        if (message.isEmpty())
            return false;

        QByteArray msg = message.toUtf8();
        QByteArray data = "MESSAGE " + QByteArray::number(msg.size()) + " " + msg;
        DB("send: '" << data.data() << "'");
        const bool success = write(data) == data.size();

        // Writes as much as possible from the internal write buffer to the
        // underlying network socket, without blocking.
        flush();

        return success;
    }

    bool Connection::sendData(const QString& interp, const QByteArray& data)
    {
        DB("sendData interp " << interp.toUtf8().data());
        QByteArray out = interp.toUtf8();
        out += " ";
        out += QByteArray::number(data.size());
        out += " ";
        out += data;
        DB("send: '" << interp.toUtf8().data() << " " << data.size() << " "
                     << "<data>'");
        return write(out) == out.size();
    }

    void Connection::timerEvent(QTimerEvent* timerEvent)
    {
        if (timerEvent->timerId() == m_transferTimerId)
        {
            cerr << "ERROR: connection timed out waiting for data transfer" << endl;
            abort();
            killTimer(m_transferTimerId);
            m_transferTimerId = 0;
        }
    }

    void Connection::processReadyRead()
    {
#ifdef DB_LEVEL
        QByteArray printable;
        for (int i = 0; i < m_buffer.size(); ++i)
        {
            if (isprint(m_buffer[i]))
                printable.append(m_buffer[i]);
        }

        DB("processReadyRead '" << printable.data() << "'");
#endif
        if (m_state == WaitingForGreeting)
        {
            if (!readProtocolHeader())
                return;

            if (m_currentDataType != Greeting && m_currentDataType != NewGreeting)
            {
                cerr << "ERROR: connection aborted because of bad greeting" << endl;
                abort();
                return;
            }

            m_state = ReadingGreeting;
        }

        if (m_state == ReadingGreeting)
        {
            if (!hasEnoughData())
                return;

            m_buffer = read(m_numBytesForCurrentDataType);
#ifdef DB_LEVEL
            QByteArray printable;
            for (int i = 0; i < m_buffer.size(); ++i)
            {
                if (isprint(m_buffer[i]))
                    printable.append(m_buffer[i]);
            }
            DB("processReadyRead '" << printable.data() << "'");
#endif

            if (m_buffer.size() != m_numBytesForCurrentDataType)
            {
                cerr << "ERROR: connection aborted because greeting data size "
                        "does not match"
                     << endl;
                abort();
                return;
            }

            readGreeting();

            QHostInfo hostInfo = QHostInfo::fromName(peerAddress().toString());

            if (hostInfo.error() == QHostInfo::NoError)
            {
                m_remoteContactName = m_remoteName + "@" + hostInfo.hostName();
            }
            else
            {
                QHostAddress addr(peerAddress().toString());

                if (addr.protocol() != QAbstractSocket::UnknownNetworkLayerProtocol)
                {
                    m_remoteContactName = m_remoteName + "@" + peerAddress().toString();
                }
                else
                {
                    m_remoteContactName = m_remoteName + "@unknown.host";
                }
            }
            m_currentDataType = Undefined;
            m_numBytesForCurrentDataType = 0;
            emit requestGreeting();
            m_buffer.clear();

            if (!isValid())
            {
                cerr << "ERROR: connection aborted reading greeting" << endl;
                abort();
                return;
            }

            if (!m_isGreetingMessageSent)
                sendGreetingMessage();

            if (m_pingpong)
            {
                m_pingTimer.start();
                m_pongTime.restart();
            }
            m_state = ReadyForUse;

            emit readyForUse();
        }

        do
        {
            if (m_currentDataType == Undefined)
            {
                if (!readProtocolHeader())
                    return;
            }

            if (!hasEnoughData())
                return;
            processData();

        } while (bytesAvailable() > 0);
    }

    void Connection::startPingPong()
    {
        DB("turning on heartbeat");
        m_pongTime.restart();
        m_pingTimer.start();
        m_pingpong = true;
    }

    void Connection::stopPingPong()
    {
        DB("turning off heartbeat");
        m_pingTimer.stop();
        m_pingpong = false;
    }

    void Connection::pingPongControl(bool ppOn)
    {
        if (ppOn)
            startPingPong();
        else
            stopPingPong();

        QString m("PINGPONGCONTROL 1 " + QString((ppOn) ? "1" : "0"));
        DB("send: '" << m.toUtf8().data() << "'");
        write(m.toUtf8().data());
    }

    void Connection::sendPing()
    {
        if (!m_pingpong)
            return;

        if (m_pongTime.elapsed() > PongTimeout)
        {
            cerr << "ERROR: connection aborted because response was too slow" << endl;
            abort();
            return;
        }

        if (isValid())
        {
            // cout << "CONNECTION: sending PING" << endl;
            DB("send: 'PING 1 p'");
            write("PING 1 p");
        }
    }

    quint16 Connection::serverPort() const { return m_incoming ? localPort() : peerPort(); }

    quint16 Connection::clientPort() const { return m_incoming ? peerPort() : localPort(); }

    //
    //  The third word of our greeting: "utv=1", then ";local=<proof>" on a
    //  loopback connection or ";pair=<proof>" if the peer gave us pairing
    //  keys.
    //
    QByteArray Connection::greetingExtensions()
    {
        QByteArray ext = "utv=1";
        const QHostAddress peer = Auth::normalized(peerAddress());

        if (peer.isLoopback())
        {
            const QString proof = Auth::makeLocalProof(m_incoming, serverPort(), clientPort());
            if (!proof.isEmpty())
                ext += ";local=" + proof.toLatin1();
        }
        else
        {
            const QString proof = Auth::makePairingProof(peer);
            if (!proof.isEmpty())
                ext += ";pair=" + proof.toLatin1();
        }

        return ext;
    }

    //
    //  Read the peer's greeting from m_buffer. GREETING carries only a name.
    //  NEWGREETING carries "<name> <app>", and from OpenUTV a third word of
    //  extensions, in which case the name is percent-encoded.
    //
    void Connection::readGreeting()
    {
        const QString greeting = QString::fromUtf8(m_buffer);
        QString localProof;

        m_remoteName = greeting;
        m_remoteApp = "rv";
        m_peerSupportsPairing = false;
        m_pairingProof.clear();
        m_local = false;

        if (m_currentDataType == NewGreeting)
        {
            m_remoteName = greeting.section(' ', 0, 0);
            m_remoteApp = greeting.section(' ', 1, 1);

            const QStringList ext = greeting.section(' ', 2, 2).split(';');

            if (ext.contains("utv=1"))
            {
                m_peerSupportsPairing = true;
                m_remoteName = QUrl::fromPercentEncoding(m_remoteName.toUtf8());

                for (const QString& field : ext)
                {
                    if (field.startsWith("local="))
                        localProof = field.mid(6);
                    else if (field.startsWith("pair="))
                        m_pairingProof = field.mid(5);
                }
            }
        }

        //
        //  A connection is local only if the peer is on this machine and
        //  proves it runs as this user. Being on the loopback address is not
        //  enough: other users on the machine can connect there too.
        //
        if (!localProof.isEmpty() && Auth::normalized(peerAddress()).isLoopback())
            m_local = Auth::checkLocalProof(localProof, !m_incoming, serverPort(), clientPort());
    }

    void Connection::sendPairingKey(const QByteArray& key)
    {
        if (m_isGreetingMessageSent)
            Connection::sendData("PAIRKEY(1)", key);
        else
            m_pendingPairingKey = key;
    }

    void Connection::sendGreetingMessage()
    {
        //
        //  Always NEWGREETING, so the extensions can follow the app name.
        //  Older receivers read the first two words and ignore the rest, and
        //  see the percent-encoded name.
        //
        const QByteArray greeting = QUrl::toPercentEncoding(m_greetingName) + " " + m_greetingApp.toUtf8() + " " + greetingExtensions();
        const QByteArray data = "NEWGREETING " + QByteArray::number(greeting.size()) + " " + greeting;

        DB("send: '" << data.data() << "'");
        if (write(data) == data.size())
        {
            m_isGreetingMessageSent = true;

            if (!m_pendingPairingKey.isEmpty())
            {
                Connection::sendData("PAIRKEY(1)", m_pendingPairingKey);
                m_pendingPairingKey.clear();
            }
        }
    }

    int Connection::readDataIntoBuffer(int maxSize)
    {
        if (maxSize > MaxBufferSize)
            return 0;

        int numBytesBeforeRead = m_buffer.size();

        if (numBytesBeforeRead == MaxBufferSize)
        {
            cerr << "ERROR: connection aborted because data load too big" << endl;
            abort();
            return 0;
        }

        while (bytesAvailable() > 0 && m_buffer.size() < maxSize)
        {
            m_buffer.append(read(1));
            if (m_buffer.endsWith(SeparatorToken))
                break;
        }

#ifdef DB_LEVEL
        QByteArray printable;
        for (int i = 0; i < m_buffer.size(); ++i)
        {
            if (isprint(m_buffer[i]))
                printable.append(m_buffer[i]);
        }
        DB("readDataInfoBuffer '" << printable.data() << "'");
#endif
        return m_buffer.size() - numBytesBeforeRead;
    }

    int Connection::dataLengthForCurrentDataType()
    {
        if (bytesAvailable() <= 0 || readDataIntoBuffer() <= 0 || !m_buffer.endsWith(SeparatorToken))
        {
            return 0;
        }

        m_buffer.chop(1);
        int number = m_buffer.toInt();
        m_buffer.clear();
        return number;
    }

    bool Connection::readProtocolHeader()
    {
        if (m_transferTimerId)
        {
            killTimer(m_transferTimerId);
            m_transferTimerId = 0;
        }

        if (readDataIntoBuffer() <= 0)
        {
            m_transferTimerId = startTimer(TransferTimeout);
            return false;
        }

        if (m_buffer == "PING ")
            m_currentDataType = Ping;
        else if (m_buffer == "PONG ")
            m_currentDataType = Pong;
        else if (m_buffer == "MESSAGE ")
            m_currentDataType = PlainText;
        else if (m_buffer == "GREETING ")
            m_currentDataType = Greeting;
        else if (m_buffer == "NEWGREETING ")
            m_currentDataType = NewGreeting;
        else if (m_buffer == "PINGPONGCONTROL ")
            m_currentDataType = PingPongControl;
        else
        {
            m_dataInterp = m_buffer;

            if (!m_dataInterp.endsWith(") "))
            {
#if 0
            cout << "ERROR: partial read on network connection "
                 << m_buffer.data()
                 << endl;
#endif

                m_dataInterp = "";
                return false;
            }

            m_currentDataType = RawData;
        }

        m_buffer.clear();
        m_numBytesForCurrentDataType = dataLengthForCurrentDataType();
        return true;
    }

    bool Connection::hasEnoughData()
    {
        if (m_transferTimerId)
        {
            QObject::killTimer(m_transferTimerId);
            m_transferTimerId = 0;
        }

        if (m_numBytesForCurrentDataType <= 0)
            m_numBytesForCurrentDataType = dataLengthForCurrentDataType();

        if (bytesAvailable() < m_numBytesForCurrentDataType || m_numBytesForCurrentDataType <= 0)
        {
            m_transferTimerId = startTimer(TransferTimeout);
            return false;
        }

        return true;
    }

    void Connection::processData()
    {
        if (!isValid())
            return;

        m_buffer = read(m_numBytesForCurrentDataType);
        DB("processData read " << m_buffer.size() << " bytes");

        if (m_buffer.size() != m_numBytesForCurrentDataType)
        {
            cerr << "ERROR: connection aborted because data size mismatch" << endl;
            abort();
            return;
        }

        switch (m_currentDataType)
        {
        case PlainText:
            DB("calling newMessage " << m_buffer.data());
            emit newMessage(m_remoteContactName, QString::fromUtf8(m_buffer));
            break;
        case RawData:
            if (m_dataInterp.startsWith("PAIRKEY("))
            {
                //  A key the peer gave us when it chose "Always Allow". Keep
                //  it for our next connection to that address.
                Auth::storeGivenPairingKey(peerAddress(), m_buffer);
                break;
            }
            emit newData(m_remoteContactName, m_dataInterp, m_buffer);
            break;
        case Ping:
            // cout << "CONNECTION: sending PONG" << endl;
            DB("send: 'PONG 1 p'");
            write("PONG 1 p");
            break;
        case Pong:
            // cout << "CONNECTION: received PONG" << endl;
            m_pongTime.restart();
            break;
        case PingPongControl:
            if (m_buffer.toInt())
                startPingPong();
            else
                stopPingPong();
            break;
        default:
            break;
        }

        //
        //  Restart the ping and pong timers. There's no need to check the
        //  connection status since we just got a message. Obviously the
        //  connection is still functional. This prevents a lot of useless
        //  chatter.
        //

        if (m_pingpong)
        {
            m_pingTimer.start();
            m_pongTime.restart();
        }
        m_currentDataType = Undefined;
        m_numBytesForCurrentDataType = 0;
        m_buffer.clear();
    }

} // namespace TwkQtChat
