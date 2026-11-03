// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "appearance.h"

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSTour;

class AppearanceTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    QString logPath() const { return m_dir.filePath(QStringLiteral("runs.log")); }
    QString plasmarc() const { return m_dir.filePath(QStringLiteral("plasmarc")); }

    // Each command appends itself to runs.log; the one named fails.
    void useRecorder(Appearance &appearance, const QString &failing = { })
    {
        const QString script = QStringLiteral("echo \"$*\" >>'%1'; [ \"$1\" != '%2' ]").arg(logPath(), failing);
        appearance.setCommandForTesting(QStringLiteral("/bin/sh"), { QStringLiteral("-c"), script, QStringLiteral("sh") });
        appearance.setPlasmaConfigForTesting(plasmarc());
    }

    QStringList runs() const
    {
        QFile file(logPath());
        if (!file.open(QIODevice::ReadOnly)) {
            return { };
        }
        return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    }

    static void writeScheme(const QString &scheme)
    {
        KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
        KConfigGroup(globals, QStringLiteral("General")).writeEntry("ColorScheme", scheme);
        globals->sync();
    }

    void writeTheme(const QString &theme) const
    {
        KConfig plasma(plasmarc());
        KConfigGroup(&plasma, QStringLiteral("Theme")).writeEntry("name", theme);
        plasma.sync();
    }

private Q_SLOTS:
    void initTestCase() { QStandardPaths::setTestModeEnabled(true); }

    void init()
    {
        QFile::remove(logPath());
        QFile::remove(plasmarc());
        writeScheme(QStringLiteral("OrielOSDark"));
    }

    void readsTheScheme()
    {
        Appearance dark;
        QVERIFY(dark.isDark());
        writeScheme(QStringLiteral("OrielOSLight"));
        Appearance light;
        QVERIFY(!light.isDark());
        writeScheme(QStringLiteral("BreezeDark"));
        QVERIFY(Appearance().isDark());
    }

    void appliesTheLookAndFeelAndItsScheme()
    {
        Appearance appearance;
        useRecorder(appearance);
        QSignalSpy applied(&appearance, &Appearance::applied);
        appearance.setDark(false);
        QVERIFY(appearance.isBusy());
        // Shown as chosen while it's applied.
        QVERIFY(!appearance.isDark());
        QVERIFY(applied.wait());
        QCOMPARE(applied.first().first().toBool(), true);
        QVERIFY(!appearance.isBusy());
        QCOMPARE(appearance.error(), QString());
        QCOMPARE(runs(),
            QStringList({ QStringLiteral("plasma-apply-lookandfeel --apply org.orielos.desktop"), QStringLiteral("plasma-apply-colorscheme OrielOSLight") }));
    }

    void sameChoiceDoesNothing()
    {
        Appearance appearance;
        useRecorder(appearance);
        appearance.setDark(true);
        QVERIFY(!appearance.isBusy());
        QVERIFY(runs().isEmpty());
    }

    void putsTheAccentThemeBack()
    {
        writeScheme(QStringLiteral("OrielOSLight"));
        writeTheme(QStringLiteral("orielos-accent"));
        Appearance appearance;
        useRecorder(appearance);
        QSignalSpy applied(&appearance, &Appearance::applied);
        appearance.setDark(true);
        QVERIFY(applied.wait());
        QCOMPARE(runs(),
            QStringList({ QStringLiteral("plasma-apply-lookandfeel --apply org.orielos.desktop.dark"), QStringLiteral("plasma-apply-colorscheme OrielOSDark"),
                QStringLiteral("plasma-apply-desktoptheme orielos-accent") }));
    }

    void plainThemeStaysAlone()
    {
        writeTheme(QStringLiteral("orielos"));
        Appearance appearance;
        useRecorder(appearance);
        QSignalSpy applied(&appearance, &Appearance::applied);
        appearance.setDark(false);
        QVERIFY(applied.wait());
        QCOMPARE(runs().size(), 2);
    }

    void schemeAlreadySetIsFine()
    {
        Appearance appearance;
        useRecorder(appearance, QStringLiteral("plasma-apply-colorscheme"));
        QSignalSpy applied(&appearance, &Appearance::applied);
        appearance.setDark(false);
        QVERIFY(applied.wait());
        QCOMPARE(applied.first().first().toBool(), true);
        QCOMPARE(appearance.error(), QString());
    }

    void failureSaysSo()
    {
        Appearance appearance;
        useRecorder(appearance, QStringLiteral("plasma-apply-lookandfeel"));
        QSignalSpy applied(&appearance, &Appearance::applied);
        appearance.setDark(false);
        QVERIFY(applied.wait());
        QCOMPARE(applied.first().first().toBool(), false);
        QVERIFY(!appearance.error().isEmpty());
        // Nothing after the look-and-feel runs.
        QCOMPARE(runs().size(), 1);
        // Back to what the colour scheme says.
        QVERIFY(appearance.isDark());
    }
};

QTEST_GUILESS_MAIN(AppearanceTest)

#include "appearancetest.moc"
