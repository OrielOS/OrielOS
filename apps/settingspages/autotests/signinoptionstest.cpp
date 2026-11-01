// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "signinoptions.h"

#include <QTest>

using namespace OrielOSSettingsPages;

// The rules the Sign-in options page checks before it asks the PIN service or writes the dynamic
// lock file.
class SignInOptionsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void pins_data()
    {
        QTest::addColumn<QString>("pin");
        QTest::addColumn<bool>("valid");
        QTest::newRow("four digits") << QStringLiteral("1234") << true;
        QTest::newRow("twelve digits") << QStringLiteral("123456789012") << true;
        QTest::newRow("three digits") << QStringLiteral("123") << false;
        QTest::newRow("thirteen digits") << QStringLiteral("1234567890123") << false;
        QTest::newRow("letters") << QStringLiteral("12a4") << false;
        QTest::newRow("space") << QStringLiteral("1234 ") << false;
        QTest::newRow("empty") << QString() << false;
    }

    void pins()
    {
        QFETCH(QString, pin);
        QFETCH(bool, valid);
        QCOMPARE(SignInOptions::isValidPin(pin), valid);
    }

    void dynamicLockFile_data()
    {
        QTest::addColumn<QByteArray>("contents");
        QTest::addColumn<QString>("address");
        QTest::newRow("written by the page") << QByteArray("device=AA:BB:CC:DD:EE:FF\n") << QStringLiteral("AA:BB:CC:DD:EE:FF");
        QTest::newRow("lower case") << QByteArray("device=0a:1b:2c:3d:4e:5f") << QStringLiteral("0A:1B:2C:3D:4E:5F");
        QTest::newRow("other lines") << QByteArray("# phone\ndevice=AA:BB:CC:DD:EE:FF\n") << QStringLiteral("AA:BB:CC:DD:EE:FF");
        QTest::newRow("too short") << QByteArray("device=AA:BB:CC:DD:EE\n") << QString();
        QTest::newRow("not hex") << QByteArray("device=GG:BB:CC:DD:EE:FF\n") << QString();
        QTest::newRow("empty") << QByteArray() << QString();
    }

    void dynamicLockFile()
    {
        QFETCH(QByteArray, contents);
        QFETCH(QString, address);
        QCOMPARE(SignInOptions::parseDynamicLockFile(contents), address);
    }

    void dynamicLockFileRoundTrip()
    {
        const QByteArray contents = SignInOptions::formatDynamicLockFile(QStringLiteral("aa:bb:cc:dd:ee:ff"));
        QCOMPARE(contents, QByteArray("device=AA:BB:CC:DD:EE:FF\n"));
        QCOMPARE(SignInOptions::parseDynamicLockFile(contents), QStringLiteral("AA:BB:CC:DD:EE:FF"));
    }
};

QTEST_GUILESS_MAIN(SignInOptionsTest)

#include "signinoptionstest.moc"
