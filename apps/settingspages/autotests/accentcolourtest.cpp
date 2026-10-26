// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "accentcolour.h"

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSSettingsPages;

class AccentColourTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    QString logPath() const { return m_dir.filePath(QStringLiteral("runs.log")); }

    // Each run appends its arguments to runs.log and exits with the given status.
    void useRecorder(AccentColour &accent, int exitCode = 0)
    {
        const QString script = QStringLiteral("echo \"$*\" >>'%1'; exit %2").arg(logPath()).arg(exitCode);
        accent.setCommandForTesting(QStringLiteral("/bin/sh"), { QStringLiteral("-c"), script, QStringLiteral("plasma-apply-colorscheme") });
    }

    QStringList runs() const
    {
        QFile file(logPath());
        if (!file.open(QIODevice::ReadOnly)) {
            return { };
        }
        return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    }

    // The AccentColor in kdeglobals, read afresh; invalid when there is none.
    static QColor recordedAccent()
    {
        KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
        globals->reparseConfiguration();
        return KConfigGroup(globals, QStringLiteral("General")).readEntry("AccentColor", QColor());
    }

    // kdeglobals with the scheme and, if valid, an accent.
    static void writeGlobals(const QString &scheme, const QColor &accent)
    {
        KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
        KConfigGroup general(globals, QStringLiteral("General"));
        general.writeEntry("ColorScheme", scheme);
        if (accent.isValid()) {
            general.writeEntry("AccentColor", accent);
        } else {
            general.deleteEntry("AccentColor");
        }
        globals->sync();
    }

private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        // A colour scheme whose selection colour is Breeze's blue.
        const QString schemes = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/color-schemes");
        QVERIFY(QDir().mkpath(schemes));
        KConfig scheme(schemes + QStringLiteral("/TestScheme.colors"), KConfig::SimpleConfig);
        KConfigGroup(&scheme, QStringLiteral("Colors:Selection")).writeEntry("BackgroundNormal", QColor(61, 174, 233));
        scheme.sync();
    }

    void init() { QFile::remove(logPath()); }

    void offersTenColours()
    {
        writeGlobals(QStringLiteral("TestScheme"), QColor());
        AccentColour accent;
        const QVariantList choices = accent.choices();
        QCOMPARE(choices.size(), 10);
        QCOMPARE(choices.first().toMap().value(QStringLiteral("name")).toString(), QStringLiteral("Blue"));
        QCOMPARE(choices.first().toMap().value(QStringLiteral("colour")).value<QColor>(), QColor(QStringLiteral("#3a66f0")));
    }

    void readsTheAccentAndTheThemesColour()
    {
        writeGlobals(QStringLiteral("TestScheme"), QColor(46, 157, 76));
        AccentColour accent;
        QCOMPARE(accent.current(), QColor(46, 157, 76));
        QCOMPARE(accent.themeColour(), QColor(61, 174, 233));

        writeGlobals(QStringLiteral("TestScheme"), QColor());
        accent.reload();
        QVERIFY(!accent.current().isValid());
        // An unknown scheme has no colour of its own to go back to.
        writeGlobals(QStringLiteral("NoSuchScheme"), QColor());
        accent.reload();
        QVERIFY(!accent.themeColour().isValid());
    }

    void appliesAColourInItsOwnProcess()
    {
        writeGlobals(QStringLiteral("TestScheme"), QColor());
        AccentColour accent;
        useRecorder(accent);
        QSignalSpy applied(&accent, &AccentColour::applied);
        accent.choose(QColor(QStringLiteral("#e0661b")));
        QVERIFY(accent.isBusy());
        // The chosen colour shows while it's applied.
        QCOMPARE(accent.current(), QColor(QStringLiteral("#e0661b")));
        // Nothing else starts meanwhile.
        accent.choose(QColor(QStringLiteral("#3a66f0")));
        QVERIFY(applied.wait());
        QCOMPARE(applied.first().first().toBool(), true);
        QVERIFY(!accent.isBusy());
        QCOMPARE(runs(), QStringList { QStringLiteral("--accent-color #e0661b") });
        QVERIFY(accent.error().isEmpty());
        // Recorded, so the next scheme applied keeps it, and shown as the one in use.
        QCOMPARE(recordedAccent(), QColor(QStringLiteral("#e0661b")));
        QCOMPARE(accent.current(), QColor(QStringLiteral("#e0661b")));
    }

    void goesBackToTheThemesColour()
    {
        writeGlobals(QStringLiteral("TestScheme"), QColor(46, 157, 76));
        AccentColour accent;
        useRecorder(accent);
        QSignalSpy applied(&accent, &AccentColour::applied);
        accent.useThemeColour();
        QVERIFY(applied.wait());
        // No accent recorded, and the scheme applied without one.
        QCOMPARE(runs(), QStringList { QStringLiteral("--accent-color transparent") });
        QVERIFY(!recordedAccent().isValid());
        QVERIFY(!accent.current().isValid());

        // Already the scheme's own: nothing to do.
        accent.useThemeColour();
        QVERIFY(!accent.isBusy());
    }

    void reportsAFailure()
    {
        writeGlobals(QStringLiteral("TestScheme"), QColor());
        AccentColour accent;
        useRecorder(accent, 1);
        QSignalSpy applied(&accent, &AccentColour::applied);
        accent.choose(QColor(QStringLiteral("#d63a3a")));
        QVERIFY(applied.wait());
        QCOMPARE(applied.first().first().toBool(), false);
        QVERIFY(!accent.error().isEmpty());
        QVERIFY(!accent.current().isValid());
        // The accent from before is back.
        QVERIFY(!recordedAccent().isValid());

        writeGlobals(QStringLiteral("TestScheme"), QColor(46, 157, 76));
        accent.reload();
        accent.choose(QColor(QStringLiteral("#d63a3a")));
        QVERIFY(applied.wait());
        QCOMPARE(recordedAccent(), QColor(46, 157, 76));
    }
};

QTEST_GUILESS_MAIN(AccentColourTest)

#include "accentcolourtest.moc"
