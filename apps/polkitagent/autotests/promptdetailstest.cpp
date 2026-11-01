// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "promptdetails.h"

#include <QTest>

namespace {
const QString pkexec = QStringLiteral("org.freedesktop.policykit.exec");
}

class PromptDetailsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void programFromTheImage()
    {
        const PromptDetails prompt = PromptDetails::from(pkexec, QStringLiteral("Run a program as another user"), QStringLiteral("The polkit project"), { },
            { { QStringLiteral("program"), QStringLiteral("/usr/libexec/orielos/sign-in-settings") },
                { QStringLiteral("command_line"), QStringLiteral("/usr/libexec/orielos/sign-in-settings startup-sound on") } });
        QCOMPARE(prompt.name, QStringLiteral("sign-in-settings"));
        QVERIFY(prompt.verified);
        QCOMPARE(prompt.publisher, QStringLiteral("OrielOS"));
        QCOMPARE(prompt.commandLine, QStringLiteral("/usr/libexec/orielos/sign-in-settings startup-sound on"));
    }

    void programsElsewhereAreUnknown_data()
    {
        QTest::addColumn<QString>("program");
        QTest::newRow("home") << QStringLiteral("/var/home/someone/install.sh");
        QTest::newRow("usr local") << QStringLiteral("/usr/local/bin/tool");
        QTest::newRow("etc") << QStringLiteral("/etc/tool");
        QTest::newRow("climbing out of usr") << QStringLiteral("/usr/../var/home/someone/tool");
        QTest::newRow("tmp") << QStringLiteral("/tmp/tool");
    }

    void programsElsewhereAreUnknown()
    {
        QFETCH(QString, program);
        const PromptDetails prompt = PromptDetails::from(pkexec, { }, { }, { }, { { QStringLiteral("program"), program } });
        QVERIFY(!prompt.verified);
        QVERIFY(prompt.publisher.isEmpty());
        QCOMPARE(prompt.program, program);
    }

    void programFromTheMessage()
    {
        // Newer polkit passes pkexec's program only in its message.
        const PromptDetails prompt = PromptDetails::from(pkexec, QStringLiteral("Run a program as another user"), QStringLiteral("The polkit project"),
            QStringLiteral("Authentication is needed to run `/var/home/someone/bin/tool' as the super user"), { });
        QCOMPARE(prompt.program, QStringLiteral("/var/home/someone/bin/tool"));
        QCOMPARE(prompt.name, QStringLiteral("tool"));
        QVERIFY(!prompt.verified);

        const PromptDetails image
            = PromptDetails::from(pkexec, { }, { }, QStringLiteral("Authentication is needed to run `/usr/bin/true' as the super user"), { });
        QVERIFY(image.verified);
        QCOMPARE(image.publisher, QStringLiteral("OrielOS"));
        QVERIFY(image.commandLine.isEmpty());

        // With arguments, the message holds the whole command line.
        const PromptDetails withArguments = PromptDetails::from(
            pkexec, { }, { }, QStringLiteral("Authentication is needed to run `/var/home/someone/bin/tool --help' as the super user"), { });
        QCOMPARE(withArguments.program, QStringLiteral("/var/home/someone/bin/tool"));
        QCOMPARE(withArguments.name, QStringLiteral("tool"));
        QCOMPARE(withArguments.commandLine, QStringLiteral("/var/home/someone/bin/tool --help"));
    }

    void serviceActions()
    {
        const PromptDetails prompt = PromptDetails::from(QStringLiteral("org.freedesktop.NetworkManager.settings.modify.system"),
            QStringLiteral("Modify network connections for all users"), QStringLiteral("NetworkManager"), { }, { });
        QCOMPARE(prompt.name, QStringLiteral("Modify network connections for all users"));
        QCOMPARE(prompt.publisher, QStringLiteral("NetworkManager"));
        QVERIFY(prompt.verified);
        QVERIFY(prompt.program.isEmpty());

        const PromptDetails bare = PromptDetails::from(QStringLiteral("org.example.action"), { }, { }, { }, { });
        QCOMPARE(bare.name, QStringLiteral("org.example.action"));
        QCOMPARE(bare.publisher, QStringLiteral("OrielOS"));
    }
};

QTEST_GUILESS_MAIN(PromptDetailsTest)

#include "promptdetailstest.moc"
