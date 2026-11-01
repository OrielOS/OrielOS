// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fpsoverlay.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSSettingsPages;

class FpsOverlayTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void readsTheStatus()
    {
        FpsOverlay overlay(QStringLiteral("/nonexistent"), nullptr);
        QVERIFY(!overlay.isEnabled());
        overlay.readStatus(QStringLiteral("enabled=on\nshown=no\nframetime=on\nstats=off\nsteam=needs-addon\n"));
        QVERIFY(overlay.isEnabled());
        QVERIFY(overlay.frameTime());
        QVERIFY(!overlay.stats());
        QVERIFY(overlay.steamNeedsAddon());
        overlay.readStatus(QStringLiteral("enabled=off\nsteam=ready\n"));
        QVERIFY(!overlay.isEnabled());
        QVERIFY(!overlay.steamNeedsAddon());
    }

    void runsTheHelper()
    {
        // A stand-in for fps-overlay that logs its arguments and reports the overlay on.
        QTemporaryDir dir;
        const QString log = dir.filePath(QStringLiteral("log"));
        const QString program = dir.filePath(QStringLiteral("fps-overlay"));
        QFile script(program);
        QVERIFY(script.open(QIODevice::WriteOnly));
        script.write(QStringLiteral("#!/bin/sh\necho \"$@\" >>'%1'\n[ \"$1\" = status ] && echo enabled=on\nexit 0\n").arg(log).toUtf8());
        script.close();
        script.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

        FpsOverlay overlay(program, nullptr);
        QVERIFY(overlay.isEnabled());
        // Already on: nothing runs.
        overlay.setEnabled(true);
        QVERIFY(!overlay.isBusy());
        QSignalSpy changed(&overlay, &FpsOverlay::changed);
        overlay.setFrameTime(true);
        QVERIFY(overlay.isBusy());
        QTRY_VERIFY(!overlay.isBusy());
        QFile logFile(log);
        QVERIFY(logFile.open(QIODevice::ReadOnly));
        QVERIFY(logFile.readAll().contains("option frametime on"));
        QVERIFY(overlay.error().isEmpty());
    }
};

QTEST_GUILESS_MAIN(FpsOverlayTest)

#include "fpsoverlaytest.moc"
