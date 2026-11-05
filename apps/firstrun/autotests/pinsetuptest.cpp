// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pinsetup.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

// A stand-in for the PIN service: records each request and answers with answer, or holds the
// connection without answering while hold is set.
class FakePinService : public QObject
{
    Q_OBJECT

public:
    explicit FakePinService(const QString &path)
    {
        connect(&m_server, &QLocalServer::newConnection, this, [this]() {
            while (QLocalSocket *socket = m_server.nextPendingConnection()) {
                connect(socket, &QLocalSocket::readyRead, socket, [this, socket]() {
                    if (!socket->canReadLine()) {
                        return;
                    }
                    requests.append(QJsonDocument::fromJson(socket->readLine()).object());
                    if (hold) {
                        held.append(socket);
                        return;
                    }
                    reply(socket);
                });
            }
        });
        QVERIFY(m_server.listen(path));
    }

    void reply(QLocalSocket *socket)
    {
        socket->write(QJsonDocument(answer).toJson(QJsonDocument::Compact) + '\n');
        socket->flush();
        socket->disconnectFromServer();
    }

    void releaseHeld()
    {
        hold = false;
        for (QLocalSocket *socket : std::as_const(held)) {
            reply(socket);
        }
        held.clear();
    }

    QList<QJsonObject> requests;
    QJsonObject answer { { QStringLiteral("ok"), true } };
    bool hold = false;
    QList<QLocalSocket *> held;

private:
    QLocalServer m_server;
};

static QJsonObject stage(const QString &user, const QString &pin)
{
    return { { QStringLiteral("op"), QStringLiteral("stage") }, { QStringLiteral("user"), user }, { QStringLiteral("pin"), pin } };
}

class PinSetupTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    QString socketPath() const { return m_dir.filePath(QStringLiteral("pin-%1.socket").arg(QLatin1String(QTest::currentTestFunction()))); }

private Q_SLOTS:
    void validPins()
    {
        QVERIFY(!PinSetup::isValidPin(QStringLiteral("123")));
        QVERIFY(PinSetup::isValidPin(QStringLiteral("1234")));
        QVERIFY(PinSetup::isValidPin(QStringLiteral("123456789012")));
        QVERIFY(!PinSetup::isValidPin(QStringLiteral("1234567890123")));
        QVERIFY(!PinSetup::isValidPin(QStringLiteral("12a4")));
        QVERIFY(!PinSetup::isValidPin(QStringLiteral("12 34")));
        // Arabic-Indic digits are digits, but not a PIN's.
        QVERIFY(!PinSetup::isValidPin(QStringLiteral("١٢٣٤")));
    }

    void savesThePin()
    {
        FakePinService service(socketPath());
        PinSetup setup;
        setup.setSocketForTesting(socketPath());
        QSignalSpy saved(&setup, &PinSetup::saved);
        setup.save(QStringLiteral("nathan"), QStringLiteral("1234"));
        QVERIFY(setup.saving());
        QVERIFY(saved.wait());
        QCOMPARE(saved.first().first().toBool(), true);
        QVERIFY(!setup.saving());
        QVERIFY(setup.error().isEmpty());
        QCOMPARE(service.requests, QList<QJsonObject> { stage(QStringLiteral("nathan"), QStringLiteral("1234")) });
    }

    void anEmptyPinTakesItBack()
    {
        FakePinService service(socketPath());
        PinSetup setup;
        setup.setSocketForTesting(socketPath());
        QSignalSpy saved(&setup, &PinSetup::saved);
        setup.save(QStringLiteral("nathan"), QString());
        QVERIFY(saved.wait());
        QCOMPARE(saved.first().first().toBool(), true);
        QCOMPARE(service.requests, QList<QJsonObject> { stage(QStringLiteral("nathan"), QString()) });
    }

    void aRefusalIsAnError()
    {
        FakePinService service(socketPath());
        service.answer = { { QStringLiteral("ok"), false }, { QStringLiteral("error"), QStringLiteral("not allowed") } };
        PinSetup setup;
        setup.setSocketForTesting(socketPath());
        QSignalSpy saved(&setup, &PinSetup::saved);
        setup.save(QStringLiteral("nathan"), QStringLiteral("1234"));
        QVERIFY(saved.wait());
        QCOMPARE(saved.first().first().toBool(), false);
        QVERIFY(!setup.error().isEmpty());
    }

    void noServiceIsAnError()
    {
        PinSetup setup;
        setup.setSocketForTesting(socketPath());
        QSignalSpy saved(&setup, &PinSetup::saved);
        setup.save(QStringLiteral("nathan"), QStringLiteral("1234"));
        QTRY_COMPARE(saved.size(), 1);
        QCOMPARE(saved.first().first().toBool(), false);
        QVERIFY(!setup.error().isEmpty());
        QVERIFY(!setup.saving());
    }

    void anInvalidPinIsNotSent()
    {
        FakePinService service(socketPath());
        PinSetup setup;
        setup.setSocketForTesting(socketPath());
        QSignalSpy saved(&setup, &PinSetup::saved);
        setup.save(QStringLiteral("nathan"), QStringLiteral("12"));
        QCOMPARE(saved.size(), 1);
        QCOMPARE(saved.first().first().toBool(), false);
        setup.save(QString(), QStringLiteral("1234"));
        QCOMPARE(saved.size(), 2);
        QCOMPARE(saved.last().first().toBool(), false);
        QTest::qWait(100);
        QVERIFY(service.requests.isEmpty());
    }

    void theSamePinIsSentOnce()
    {
        FakePinService service(socketPath());
        PinSetup setup;
        setup.setSocketForTesting(socketPath());
        QSignalSpy saved(&setup, &PinSetup::saved);
        setup.save(QStringLiteral("nathan"), QStringLiteral("1234"));
        QVERIFY(saved.wait());
        setup.save(QStringLiteral("nathan"), QStringLiteral("1234"));
        QCOMPARE(saved.size(), 2);
        QCOMPARE(saved.last().first().toBool(), true);
        QCOMPARE(service.requests.size(), 1);
        // Another account name, as after going back to the account page, is sent again.
        setup.save(QStringLiteral("nat"), QStringLiteral("1234"));
        QVERIFY(saved.wait());
        QCOMPARE(service.requests.size(), 2);
        QCOMPARE(service.requests.last(), stage(QStringLiteral("nat"), QStringLiteral("1234")));
    }

    void aSaveWhileOneRunsIsSentAfterIt()
    {
        FakePinService service(socketPath());
        service.hold = true;
        PinSetup setup;
        setup.setSocketForTesting(socketPath());
        QSignalSpy saved(&setup, &PinSetup::saved);
        setup.save(QStringLiteral("nathan"), QStringLiteral("1234"));
        QTRY_COMPARE(service.requests.size(), 1);
        setup.save(QStringLiteral("nathan"), QStringLiteral("5678"));
        setup.save(QStringLiteral("nathan"), QStringLiteral("2468"));
        QCOMPARE(service.requests.size(), 1);
        service.releaseHeld();
        QTRY_COMPARE(saved.size(), 2);
        QCOMPARE(service.requests.size(), 2);
        QCOMPARE(service.requests.last(), stage(QStringLiteral("nathan"), QStringLiteral("2468")));
        QVERIFY(saved.last().first().toBool());
    }
};

QTEST_GUILESS_MAIN(PinSetupTest)
#include "pinsetuptest.moc"
