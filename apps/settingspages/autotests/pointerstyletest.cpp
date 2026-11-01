// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pointerstyle.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using OrielOSSettingsPages::PointerStyle;

class PointerStyleTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    // A kcminputrc with these contents, and a stand-in for plasma-apply-cursortheme that records
    // its arguments in a file.
    QString setUp(PointerStyle &pointer, const QByteArray &contents, int exitCode = 0)
    {
        const QString config = m_dir.filePath(QStringLiteral("kcminputrc-%1").arg(QTest::currentTestFunction()));
        QFile file(config);
        if (!file.open(QIODevice::WriteOnly)) {
            return { };
        }
        file.write(contents);
        file.close();
        const QString record = m_dir.filePath(QStringLiteral("args-%1").arg(QTest::currentTestFunction()));
        pointer.setForTesting(config, QStringLiteral("sh"),
            { QStringLiteral("-c"), QStringLiteral("echo \"$@\" > %1; exit %2").arg(record).arg(exitCode), QStringLiteral("apply") });
        return record;
    }

    static QString read(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed() : QString();
    }

private Q_SLOTS:
    void readsPlasmasDefaults()
    {
        PointerStyle pointer;
        setUp(pointer, "");
        QVERIFY(!pointer.isWhite());
        QCOMPARE(pointer.size(), 24);
    }

    void readsTheSettings()
    {
        PointerStyle pointer;
        setUp(pointer, "[Mouse]\ncursorTheme=Breeze_Light\ncursorSize=48\n");
        QVERIFY(pointer.isWhite());
        QCOMPARE(pointer.size(), 48);
    }

    void appliesAColourKeepingTheSize()
    {
        PointerStyle pointer;
        const QString record = setUp(pointer, "[Mouse]\ncursorSize=32\n");
        QSignalSpy applied(&pointer, &PointerStyle::applied);
        pointer.setWhite(true);
        QVERIFY(pointer.isBusy());
        QVERIFY(applied.wait());
        QCOMPARE(applied.first().first().toBool(), true);
        QCOMPARE(read(record), QStringLiteral("--size 32 Breeze_Light"));
        QVERIFY(!pointer.isBusy());
    }

    void appliesASizeKeepingTheColour()
    {
        PointerStyle pointer;
        const QString record = setUp(pointer, "[Mouse]\ncursorTheme=Breeze_Light\n");
        QSignalSpy applied(&pointer, &PointerStyle::applied);
        pointer.setSize(200);
        QVERIFY(applied.wait());
        // Kept to the largest size offered.
        QCOMPARE(read(record), QStringLiteral("--size 96 Breeze_Light"));
    }

    void reportsAFailure()
    {
        PointerStyle pointer;
        setUp(pointer, "", 1);
        QSignalSpy applied(&pointer, &PointerStyle::applied);
        pointer.setWhite(true);
        QVERIFY(applied.wait());
        QCOMPARE(applied.first().first().toBool(), false);
        QVERIFY(!pointer.error().isEmpty());
    }

    void unchangedRunsNothing()
    {
        PointerStyle pointer;
        setUp(pointer, "");
        pointer.setWhite(false);
        pointer.setSize(24);
        QVERIFY(!pointer.isBusy());
    }
};

QTEST_GUILESS_MAIN(PointerStyleTest)

#include "pointerstyletest.moc"
